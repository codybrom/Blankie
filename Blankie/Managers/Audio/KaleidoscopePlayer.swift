//
//  KaleidoscopePlayer.swift
//  Blankie
//
//  Created by Cody Bromley on 11/2/26.
//

import AVFoundation
import Foundation
import os

/// Plays a `KaleidoscopeRecipe` live through an `AVAudioSourceNode`: a bank of detuned sine
/// tones shaped by each layer's motion, slow auto-pan, and an attack ramp.
/// It feeds the same gain stage as `SoundPlayer`, so volume, boost and fades match.
///
/// Threading: the render block reads `Renderer` and owns `VoiceBox`. The main thread
/// only writes `Renderer` fields, and never touches the voices after init.
final class KaleidoscopePlayer: EngineSoundPlayer {

  /// Oscillator parameters. Each tone plays as two detuned voices, so `increments`
  /// and `levels` hold two entries per tone and the rest hold one.
  struct RenderState: Sendable {
    var increments: [Double]
    var levels: [Float]
    /// Each tone's motion as gain, one value a second. Empty means the tone holds steady.
    var motion: [[Float]]
    var motionDepth: [Double]
    var motionSpeed: [Double]
    var panWidth: [Double]
    var driftSpeed: Double
    var earLagSec: Double
    var attackSec: Double
    var sampleRate: Double
  }

  /// Oscillator phases per channel, plus the RNG that seeds them.
  struct VoiceState: Sendable {
    var phasesL: [Double] = []
    var phasesR: [Double] = []
    var rng: UInt64 = 0x9E37_79B9_7F4A_7C15

    nonisolated static func seeded(count: Int, rng: inout UInt64) -> VoiceState {
      VoiceState(
        phasesL: (0..<count).map { _ in KaleidoscopePlayer.nextUnit(&rng) * 2 * .pi },
        phasesR: (0..<count).map { _ in KaleidoscopePlayer.nextUnit(&rng) * 2 * .pi },
        rng: rng)
    }

    /// New random phases, so no two plays beat alike.
    nonisolated mutating func reseed() {
      self = Self.seeded(count: phasesL.count, rng: &rng)
    }
  }

  /// Scalars shared with the render block. Writes are word-sized and happen between
  /// callbacks, so a stale read only delays a change by one buffer.
  final class Renderer: @unchecked Sendable {
    nonisolated(unsafe) var rendering = false
    nonisolated(unsafe) var volume: Float = 1
    nonisolated(unsafe) var renderedFrames: AVAudioFramePosition = 0
    /// Asks the render block to reseed its voices on the next callback.
    nonisolated(unsafe) var pendingReseed = false
  }

  /// Voices owned by the render block. Reseeding them from the main thread raced
  /// the IO thread, so reseeds go through `Renderer.pendingReseed`.
  final class VoiceBox: @unchecked Sendable {
    nonisolated(unsafe) var voices: VoiceState
    nonisolated init(_ voices: VoiceState) {
      self.voices = voices
    }
  }

  let node: AVAudioSourceNode
  let gain: AVAudioUnitEQ
  let connectionFormat: AVAudioFormat
  var engineNode: AVAudioNode { node }
  var onPlaybackFinished: (() -> Void)?

  private let renderer = Renderer()

  private(set) var isPlaying = false
  private(set) var isFadingToSilence = false
  private(set) var fadeLevel: Float = 1
  private var baseVolume: Float = 1
  private var fadeTimer: Timer?
  private var fadeStep = 0
  private var fadeCompletion: (() -> Void)?

  var volume: Float {
    get { baseVolume }
    set {
      baseVolume = newValue
      renderer.volume = baseVolume * fadeLevel
    }
  }

  var isSpatial: Bool { false }
  var isMonoSource: Bool { false }
  var loops: Bool { true }
  var duration: TimeInterval { .infinity }
  var totalFrames: AVAudioFramePosition { .max / 4 }
  var sampleRate: Double { connectionFormat.sampleRate }
  var currentFrame: AVAudioFramePosition { renderer.renderedFrames }
  var currentTime: TimeInterval { Double(currentFrame) / sampleRate }

  init(recipe: KaleidoscopeRecipe) {
    // 32 kHz keeps the oscillator bank cheap and still clears the top partial
    // (~11 kHz). The mixer resamples to the hardware rate.
    let format = AVAudioFormat(standardFormatWithSampleRate: 32000, channels: 2)!
    connectionFormat = format
    gain = AVAudioUnitEQ(numberOfBands: 0)
    gain.globalGain = 0
    let state = Self.renderState(for: recipe, sampleRate: format.sampleRate)
    var rng = UInt64.random(in: 1...UInt64.max)
    let voices = VoiceBox(.seeded(count: state.increments.count, rng: &rng))
    node = Self.makeSourceNode(format: format, renderer: renderer, state: state, voices: voices)
  }

  func setBoostDB(_ db: Float) {
    gain.globalGain = max(0, db)
  }

  /// Nothing to capture: the frame counter survives an engine rebuild.
  func freeze() {}

  // MARK: - Transport

  func play(fromFrame: AVAudioFramePosition) {
    guard node.engine != nil else {
      Logger.sounds.error("KaleidoscopePlayer: play skipped — node not attached to an engine")
      return
    }
    let from = max(0, fromFrame)
    if from == 0 {
      renderer.pendingReseed = true
    }
    renderer.renderedFrames = from
    renderer.volume = baseVolume * fadeLevel
    renderer.rendering = true
    isPlaying = true
  }

  func pause() {
    renderer.rendering = false
    isPlaying = false
  }

  func stop() {
    fadeTimer?.invalidate()
    fadeCompletion = nil
    isFadingToSilence = false
    renderer.rendering = false
    renderer.renderedFrames = 0
    renderer.pendingReseed = true
    isPlaying = false
  }

  func seek(toFrame frame: AVAudioFramePosition) {
    renderer.rendering = false
    renderer.renderedFrames = max(0, frame)
    isPlaying = false
  }

  // MARK: - Fades (same semantics as SoundPlayer)

  func setFadeLevel(_ level: Float) {
    fadeTimer?.invalidate()
    fadeCompletion = nil
    isFadingToSilence = false
    applyFadeLevel(level)
  }

  func fade(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
    fadeTimer?.invalidate()
    fadeCompletion = nil
    let clampedTarget = max(0, min(target, 1))
    guard duration > 0, abs(clampedTarget - fadeLevel) > 0.001 else {
      isFadingToSilence = false
      applyFadeLevel(clampedTarget)
      completion?()
      return
    }
    isFadingToSilence = clampedTarget == 0
    let start = fadeLevel
    let steps = max(Int(duration * 30), 1)
    let stepDuration = duration / Double(steps)
    fadeStep = 0
    fadeCompletion = completion
    let timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) {
      [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      let isFinalStep = MainActor.assumeIsolated { () -> Bool in
        self.fadeStep += 1
        self.applyFadeLevel(start + (clampedTarget - start) * Float(self.fadeStep) / Float(steps))
        return self.fadeStep >= steps
      }
      guard isFinalStep else { return }
      // Invalidate the firing timer, not `self.fadeTimer`: a completion that chains a
      // new fade has already replaced that one.
      timer.invalidate()
      MainActor.assumeIsolated {
        self.isFadingToSilence = false
        self.applyFadeLevel(clampedTarget)
        let done = self.fadeCompletion
        self.fadeCompletion = nil
        done?()
      }
    }
    timer.tolerance = stepDuration * 0.1
    RunLoop.main.add(timer, forMode: .common)
    fadeTimer = timer
  }

  private func applyFadeLevel(_ level: Float) {
    fadeLevel = max(0, min(level, 1))
    renderer.volume = baseVolume * fadeLevel
  }

  // MARK: - Rendering

  /// Output scale that keeps a full partial bank under 0 dBFS.
  nonisolated static let headroom = 0.25

  /// Partial levels are scaled down to sum to this, so dense recipes can't clip.
  nonisolated static let targetLevelSum = 2.8

  /// Gains are held for this many frames. Envelopes move once a second, so the
  /// steps are inaudible and the inner loop stays cheap.
  nonisolated static let gainBlockFrames = 512

  /// Auto-pan periods in seconds, incommensurate so voices never fall into a pattern.
  nonisolated static let panPeriods = [91.0, 67.0, 53.0, 41.0, 29.0, 23.0, 19.0, 13.0]

  /// Voices per tone: one below its pitch and one above.
  nonisolated static let voicesPerTone = 2

  nonisolated static func renderState(for recipe: KaleidoscopeRecipe, sampleRate: Double) -> RenderState {
    let levelSum = recipe.layers.flatMap(\.tones).reduce(0) { $0 + pow(10, $1.db / 20) }
    let scale = levelSum > targetLevelSum ? targetLevelSum / levelSum : 1
    var state = RenderState(
      increments: [], levels: [], motion: [], motionDepth: [], motionSpeed: [], panWidth: [],
      driftSpeed: recipe.driftSpeed, earLagSec: recipe.earLagSec,
      attackSec: recipe.attackSec, sampleRate: sampleRate)
    for layer in recipe.layers {
      let gain = pow(10, layer.gainDB / 20)
      for (index, tone) in layer.tones.enumerated() {
        for cents in [-layer.detuneCents, layer.detuneCents] {
          let hz = tone.hz * pow(2, cents / 1200)
          state.increments.append(2 * Double.pi * hz / sampleRate)
          state.levels.append(
            Float(pow(10, tone.db / 20) * scale * gain / Double(voicesPerTone)))
        }
        state.motion.append(tone.motion(in: layer, index: index, loopSec: recipe.loopSec))
        state.motionDepth.append(layer.motionDepth)
        state.motionSpeed.append(layer.motionSpeed)
        state.panWidth.append(layer.panWidth)
      }
    }
    return state
  }

  /// Renders stereo frames from `startFrame`, advancing `voices`. Pure, so tests run
  /// the same code the render block does.
  nonisolated static func render(
    state: RenderState, voices: inout VoiceState, startFrame: AVAudioFramePosition,
    volume: Float, left: UnsafeMutableBufferPointer<Float>,
    right: UnsafeMutableBufferPointer<Float>
  ) {
    let frameCount = min(left.count, right.count)
    let lagFrames = state.earLagSec * state.sampleRate
    var blockStart = 0
    while blockStart < frameCount {
      let blockLength = min(gainBlockFrames, frameCount - blockStart)
      let base = Double(startFrame) + Double(blockStart)
      let mid = base + Double(blockLength) * 0.5
      let (gainsL, gainsR) = voiceGains(state: state, frameL: mid, frameR: mid - lagFrames)
      for offset in 0..<blockLength {
        let scale =
          attackFactor(absoluteFrame: base + Double(offset), state: state)
          * Double(volume) * headroom
        let frame = blockStart + offset
        left[frame] = Float(
          mixVoices(phases: &voices.phasesL, gains: gainsL, increments: state.increments) * scale)
        right[frame] = Float(
          mixVoices(phases: &voices.phasesR, gains: gainsR, increments: state.increments) * scale)
      }
      blockStart += blockLength
    }
  }

  /// Per-voice gains: level × pan × motion. The right ear hears the motion late.
  nonisolated private static func voiceGains(
    state: RenderState, frameL: Double, frameR: Double
  ) -> (l: [Double], r: [Double]) {
    let seconds = frameL / state.sampleRate * state.driftSpeed
    var gainsL = [Double](repeating: 0, count: state.increments.count)
    var gainsR = [Double](repeating: 0, count: state.increments.count)
    for partial in 0..<state.motion.count {
      let period = panPeriods[partial % panPeriods.count]
      let pan =
        0.5 + state.panWidth[partial] * 0.35
        * sin(2 * .pi * seconds / period + Double(partial) * 2.39996)
      let panL = cos(pan * .pi / 2)
      let panR = sin(pan * .pi / 2)
      let envelopeL = envelopeGain(state: state, partial: partial, absoluteFrame: frameL)
      let envelopeR = envelopeGain(state: state, partial: partial, absoluteFrame: frameR)
      for voice in 0..<voicesPerTone {
        let index = partial * voicesPerTone + voice
        let level = Double(state.levels[index])
        gainsL[index] = level * panL * envelopeL
        gainsR[index] = level * panR * envelopeR
      }
    }
    return (gainsL, gainsR)
  }

  /// Sums one frame of the oscillator bank, advancing the phases.
  nonisolated private static func mixVoices(
    phases: inout [Double], gains: [Double], increments: [Double]
  ) -> Double {
    var sample = 0.0
    for index in 0..<increments.count {
      phases[index] += increments[index]
      if phases[index] > 2 * .pi { phases[index] -= 2 * .pi }
      sample += gains[index] * fastSin(phases[index])
    }
    return sample
  }

  /// Minimax sine for x in [0, 2π), max error ~1e-9 and about 3× faster than `sin`.
  nonisolated static func fastSin(_ x: Double) -> Double {
    var v = x
    var sign = 1.0
    if v > .pi {
      v -= .pi
      sign = -1
    }
    if v > .pi / 2 { v = .pi - v }
    let s = v * v
    var poly = 1.58969007293324801002e-10
    poly = poly * s - 2.50507602534068634195e-8
    poly = poly * s + 2.75573137070700676768e-6
    poly = poly * s - 1.98412698298579493134e-4
    poly = poly * s + 8.33333333332248946124e-3
    poly = poly * s - 1.66666666666666307295e-1
    poly = poly * s + 1
    return sign * v * poly
  }

  /// A tone's motion at a frame, interpolated and wrapped. 1 without motion.
  nonisolated static func envelopeGain(
    state: RenderState, partial: Int, absoluteFrame: Double
  ) -> Double {
    let track = state.motion[partial]
    guard !track.isEmpty else { return 1 }
    let position = absoluteFrame / state.sampleRate * state.motionSpeed[partial]
    let row0 = ((Int(floor(position)) % track.count) + track.count) % track.count
    let row1 = (row0 + 1) % track.count
    let frac = position - floor(position)
    let gain = Double(track[row0]) * (1 - frac) + Double(track[row1]) * frac
    let depth = state.motionDepth[partial]
    return depth == 1 ? gain : pow(gain, depth)
  }

  /// Raised-cosine attack, so every play swells in from silence.
  nonisolated static func attackFactor(absoluteFrame: Double, state: RenderState) -> Double {
    let attackFrames = state.attackSec * state.sampleRate
    guard attackFrames > 0, absoluteFrame < attackFrames else { return 1 }
    return 0.5 - 0.5 * cos(.pi * absoluteFrame / attackFrames)
  }

  /// Xorshift64* in [0, 1). Keeps libc's RNG off the real-time thread.
  nonisolated static func nextUnit(_ s: inout UInt64) -> Double {
    if s == 0 { s = 0x9E37_79B9_7F4A_7C15 }
    s ^= s >> 12
    s ^= s << 25
    s ^= s >> 27
    return Double((s &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
  }

  /// Must stay `nonisolated`: the engine calls the block on the real-time thread,
  /// and a main-actor block traps there.
  nonisolated private static func makeSourceNode(
    format: AVAudioFormat, renderer: Renderer, state: RenderState, voices: VoiceBox
  ) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      if renderer.pendingReseed {
        renderer.pendingReseed = false
        voices.voices.reseed()
      }
      guard renderer.rendering, buffers.count >= 2,
        let leftData = buffers[0].mData, let rightData = buffers[1].mData
      else {
        for buffer in buffers {
          if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        return noErr
      }
      let frames = Int(frameCount)
      Self.render(
        state: state, voices: &voices.voices, startFrame: renderer.renderedFrames,
        volume: renderer.volume,
        left: UnsafeMutableBufferPointer(
          start: leftData.assumingMemoryBound(to: Float.self), count: frames),
        right: UnsafeMutableBufferPointer(
          start: rightData.assumingMemoryBound(to: Float.self), count: frames))
      renderer.renderedFrames += AVAudioFramePosition(frameCount)
      return noErr
    }
  }
}
