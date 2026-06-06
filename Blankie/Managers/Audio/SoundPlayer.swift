//
//  SoundPlayer.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Accelerate
import Foundation
import os

/// Per-sound engine playback unit (replaces `AVAudioPlayer`). Wraps an
/// `AVAudioPlayerNode` plus a gain stage and handles scheduling, looping, and
/// frame-accurate position tracking for one sound.
///
/// Threading: call public methods from the main thread. Node completion
/// handlers arrive on internal queues and hop to `DispatchQueue.main` before
/// touching mutable state; stale completions are fenced by `generation`.
final class SoundPlayer {

  /// Files at or below this duration decode fully into a looping buffer;
  /// longer files stream in chunks to bound memory.
  static let bufferThreshold: TimeInterval = 90.0

  /// Streaming chunk length; the queue keeps roughly two of these scheduled.
  static let streamChunkSeconds: TimeInterval = 30.0

  enum Mode {
    case buffered(AVAudioPCMBuffer)
    case streaming
  }

  let node: AVAudioPlayerNode
  let gain: AVAudioUnitEQ
  let file: AVAudioFile
  let totalFrames: AVAudioFramePosition
  let sampleRate: Double
  let mode: Mode
  let loops: Bool
  /// Experimental: mono-folded for the 3D environment chain (the environment
  /// node only spatializes mono inputs). Normalization boost is baked into
  /// the fold since the EQ stage isn't in the spatial chain.
  let isSpatial: Bool
  /// Stable identifier used to derive this sound's 3D position.
  let sourceName: String

  /// Owner-set callback fired once when a non-looping sound finishes playback.
  var onPlaybackFinished: (() -> Void)?

  /// Preset-defined position in the spatial field (nil = stable default slot).
  var spatialPosition: AVAudio3DPoint?

  // Absolute file frame at which the current schedule started.
  private var segmentBaseFrame: AVAudioFramePosition = 0
  // Continuously memoized position: refreshed by every live currentFrame read
  // (UI polls at 30fps), so it survives the engine dying out from under us
  // (interruption/config change kill playerTime before we can react).
  private var lastKnownFrame: AVAudioFramePosition?
  // Next file frame the streaming path will schedule.
  private var streamNextFrame: AVAudioFramePosition = 0
  // Bumped on stop() to invalidate in-flight completion handlers. NOT bumped on
  // pause(): queued streaming chunks survive a pause and must keep their
  // completions valid so the chain resumes.
  private var generation: Int = 0
  // Fade layer: node.volume = baseVolume × fadeLevel. updateVolume() owns the
  // base; play/pause transitions animate the fade.
  private var baseVolume: Float = 1
  private(set) var fadeLevel: Float = 1
  private var fadeTimer: Timer?

  /// True while a fade is ramping toward silence (pause/stop intent). Lets
  /// the engine rebuild skip resurrecting a node that is audibly fading out
  /// but already logically paused.
  private(set) var isFadingToSilence = false

  // MARK: - Init

  init(fileURL: URL, loops: Bool, spatial: Bool = false, spatialBoostDB: Float = 0) throws {
    self.loops = loops
    self.sourceName = fileURL.lastPathComponent

    let sourceFile = try AVAudioFile(forReading: fileURL)
    let sourceRate = sourceFile.processingFormat.sampleRate
    let sourceDuration = sourceRate > 0 ? Double(sourceFile.length) / sourceRate : 0
    let isLong = sourceDuration > SoundPlayer.bufferThreshold

    let chosenFile: AVAudioFile
    let chosenMode: Mode
    let chosenSpatial: Bool

    if spatial, isLong,
      let cacheURL = SpatialAudioCache.existingCache(for: fileURL, boostDB: spatialBoostDB),
      let cacheFile = try? AVAudioFile(forReading: cacheURL)
    {
      // Stream the rendered mono variant; its segments feed the environment
      // node directly (boost is baked into the render).
      chosenFile = cacheFile
      chosenMode = .streaming
      chosenSpatial = true
      Logger.sounds.debug(
        "SoundPlayer: Streaming spatial mono cache for '\(fileURL.lastPathComponent)'")
    } else if !isLong,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: sourceFile.processingFormat,
        frameCapacity: AVAudioFrameCount(max(sourceFile.length, 1)))
    {
      try sourceFile.read(into: buffer)
      chosenFile = sourceFile
      if spatial, let mono = Self.monoFold(of: buffer, gainDB: spatialBoostDB) {
        chosenMode = .buffered(mono)
        chosenSpatial = true
        Logger.sounds.debug(
          "SoundPlayer: Spatial mono fold '\(fileURL.lastPathComponent)' (+\(spatialBoostDB) dB baked)"
        )
      } else {
        chosenMode = .buffered(buffer)
        chosenSpatial = false
        Logger.sounds.debug(
          "SoundPlayer: Buffered '\(fileURL.lastPathComponent)' (\(sourceDuration)s)")
      }
    } else {
      // Long without a mono cache (or buffer alloc failed): stream flat. The
      // spatial mixer offers "prepare" to render the cache.
      chosenFile = sourceFile
      chosenMode = .streaming
      chosenSpatial = false
      Logger.sounds.debug(
        "SoundPlayer: Streaming '\(fileURL.lastPathComponent)' (\(sourceDuration)s)\(spatial && isLong ? " - spatial needs preparation" : "")"
      )
    }

    self.file = chosenFile
    self.mode = chosenMode
    self.isSpatial = chosenSpatial
    self.totalFrames = chosenFile.length
    self.sampleRate = chosenFile.processingFormat.sampleRate
    self.node = AVAudioPlayerNode()
    self.gain = AVAudioUnitEQ(numberOfBands: 0)
    self.gain.globalGain = 0
  }

  /// Averages all channels into a mono buffer with the normalization boost
  /// baked in (hard-capped at full scale; the fold is for the spatial chain).
  /// Shared with SpatialAudioCache's chunked offline render.
  static func monoFold(of buffer: AVAudioPCMBuffer, gainDB: Float) -> AVAudioPCMBuffer? {
    guard let src = buffer.floatChannelData,
      let monoFormat = AVAudioFormat(
        standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1),
      let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
      let dst = mono.floatChannelData?.pointee
    else { return nil }

    let count = vDSP_Length(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)

    if channels == 1 {
      dst.update(from: src[0], count: Int(buffer.frameLength))
    } else {
      var scale = 1.0 / Float(channels)
      vDSP_vsmul(src[0], 1, &scale, dst, 1, count)
      for channel in 1..<channels {
        vDSP_vsma(src[channel], 1, &scale, dst, 1, dst, 1, count)
      }
    }

    if gainDB > 0 {
      var gain = pow(10, gainDB / 20)
      vDSP_vsmul(dst, 1, &gain, dst, 1, count)
      var floor: Float = -1
      var ceiling: Float = 1
      vDSP_vclip(dst, 1, &floor, &ceiling, dst, 1, count)
    }

    mono.frameLength = buffer.frameLength
    return mono
  }

  // MARK: - State

  var isPlaying: Bool { node.isPlaying }

  var duration: TimeInterval { sampleRate > 0 ? Double(totalFrames) / sampleRate : 0 }

  /// Current absolute playback position in frames: derived from the node's
  /// render timeline when playing, memoized cache when paused/stopped/rebuilding.
  var currentFrame: AVAudioFramePosition {
    guard totalFrames > 0 else { return 0 }
    if node.isPlaying, let renderTime = node.lastRenderTime,
      let playerTime = node.playerTime(forNodeTime: renderTime)
    {
      // sampleTime can be negative for a render cycle right after play().
      let played = max(playerTime.sampleTime, 0)
      let absolute = segmentBaseFrame + played
      let frame = loops ? absolute % totalFrames : min(absolute, totalFrames)
      lastKnownFrame = frame
      return frame
    }
    return lastKnownFrame ?? segmentBaseFrame
  }

  /// Whether the source is mono (the mixer pans mono inputs ≈3 dB down;
  /// updateVolume compensates).
  var isMonoSource: Bool { file.processingFormat.channelCount == 1 }

  var currentTime: TimeInterval { sampleRate > 0 ? Double(currentFrame) / sampleRate : 0 }

  var volume: Float {
    get { baseVolume }
    set {
      baseVolume = newValue
      applyVolume()
    }
  }

  /// Boost gain in dB (≥ 0; attenuation lives in `volume`).
  func setBoostDB(_ db: Float) {
    gain.globalGain = max(0, db)
  }

  // MARK: - Fades

  private func applyVolume() {
    node.volume = baseVolume * fadeLevel
  }

  /// Sets the fade layer instantly (e.g. to 0 just before a fade-in starts).
  func setFadeLevel(_ level: Float) {
    fadeTimer?.invalidate()
    isFadingToSilence = false
    fadeLevel = max(0, min(level, 1))
    applyVolume()
  }

  /// Linearly ramps the fade layer at 30 steps/sec. Starting a new fade (or a
  /// stop/seek) cancels the previous one — its completion never fires.
  func fade(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
    fadeTimer?.invalidate()
    let clampedTarget = max(0, min(target, 1))
    guard duration > 0, abs(clampedTarget - fadeLevel) > 0.001 else {
      isFadingToSilence = false
      fadeLevel = clampedTarget
      applyVolume()
      completion?()
      return
    }
    isFadingToSilence = clampedTarget == 0

    let start = fadeLevel
    let steps = max(Int(duration * 30), 1)
    let stepDuration = duration / Double(steps)
    var currentStep = 0

    let timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) {
      [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      currentStep += 1
      let progress = Float(currentStep) / Float(steps)
      self.fadeLevel = start + (clampedTarget - start) * progress
      self.applyVolume()

      if currentStep >= steps {
        timer.invalidate()
        self.isFadingToSilence = false
        self.fadeLevel = clampedTarget
        self.applyVolume()
        completion?()
      }
    }
    timer.tolerance = stepDuration * 0.1
    // .common keeps fades smooth while the user is scrolling.
    RunLoop.main.add(timer, forMode: .common)
    fadeTimer = timer
  }

  // MARK: - Playback

  /// Starts playback from `fromFrame`, flushing any prior schedule first so
  /// resume-from-pause is a deterministic reschedule (robust to the engine
  /// having been stopped/rebuilt in between). Call while attached to a
  /// running engine.
  func play(fromFrame: AVAudioFramePosition, completion: (() -> Void)? = nil) {
    generation += 1
    if node.engine != nil {
      node.stop()
    }

    let start = max(0, min(fromFrame, max(totalFrames - 1, 0)))
    segmentBaseFrame = start
    lastKnownFrame = start
    if let completion { onPlaybackFinished = completion }

    let scheduleGeneration = generation

    switch mode {
    case .buffered(let buffer):
      if loops {
        scheduleBufferedLoop(buffer, fromFrame: start)
      } else if isSpatial {
        // Slice the mono fold from the start frame (file segments carry the
        // source channel count and can't feed the mono chain).
        let toPlay = Self.slice(of: buffer, from: start) ?? buffer
        node.scheduleBuffer(toPlay, at: nil, completionCallbackType: .dataPlayedBack) {
          [weak self] _ in
          self?.fireFinishedIfCurrent(scheduleGeneration)
        }
      } else {
        scheduleBufferedOnce(fromFrame: start, generation: scheduleGeneration)
      }
    case .streaming:
      streamNextFrame = start
      // Prime two chunks; subsequent chunks self-schedule on .dataConsumed.
      scheduleNextStreamChunk(generation: scheduleGeneration)
      scheduleNextStreamChunk(generation: scheduleGeneration)
    }

    node.play()
    Logger.sounds.debug("SoundPlayer: play(fromFrame: \(start)) loops=\(self.loops)")
  }

  /// Buffered + looping: play the tail from `fromFrame` once, then loop the
  /// whole buffer gaplessly forever.
  private func scheduleBufferedLoop(_ buffer: AVAudioPCMBuffer, fromFrame: AVAudioFramePosition) {
    if fromFrame > 0 {
      if isSpatial {
        // File segments carry the source channel count and can't feed the
        // mono chain; slice the tail out of the mono fold instead.
        if let tail = Self.slice(of: buffer, from: fromFrame) {
          node.scheduleBuffer(tail, at: nil, completionHandler: nil)
        }
      } else {
        let tail = AVAudioFrameCount(totalFrames - fromFrame)
        node.scheduleSegment(
          file, startingFrame: fromFrame, frameCount: tail, at: nil, completionHandler: nil)
      }
    }
    node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
  }

  /// A copy of `buffer` from `frame` to its end, or nil when the slice would
  /// be empty (frame 0 callers should just use the whole buffer).
  private static func slice(
    of buffer: AVAudioPCMBuffer, from frame: AVAudioFramePosition
  ) -> AVAudioPCMBuffer? {
    let total = AVAudioFramePosition(buffer.frameLength)
    guard frame > 0, frame < total,
      let src = buffer.floatChannelData,
      let out = AVAudioPCMBuffer(
        pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(total - frame)),
      let dst = out.floatChannelData
    else { return nil }

    let count = Int(total - frame)
    for channel in 0..<Int(buffer.format.channelCount) {
      dst[channel].update(from: src[channel] + Int(frame), count: count)
    }
    out.frameLength = AVAudioFrameCount(count)
    return out
  }

  /// Buffered, non-looping: play the segment once, then fire the finished callback.
  private func scheduleBufferedOnce(fromFrame: AVAudioFramePosition, generation: Int) {
    let count = AVAudioFrameCount(totalFrames - fromFrame)
    node.scheduleSegment(
      file, startingFrame: fromFrame, frameCount: count, at: nil,
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      self?.fireFinishedIfCurrent(generation)
    }
  }

  /// Streaming: schedule one chunk from `streamNextFrame`. `.dataConsumed`
  /// completion queues the next chunk (wrapping for loops); the final
  /// non-looping chunk fires the finished callback on `.dataPlayedBack`.
  /// Never calls `node.stop()` here (documented completion-handler deadlock).
  private func scheduleNextStreamChunk(generation: Int) {
    guard generation == self.generation else { return }
    if streamNextFrame >= totalFrames {
      guard loops else { return }
      streamNextFrame = 0
    }

    let chunkFrames = AVAudioFrameCount(SoundPlayer.streamChunkSeconds * sampleRate)
    let count = min(chunkFrames, AVAudioFrameCount(totalFrames - streamNextFrame))
    let chunkStart = streamNextFrame
    let isLastChunk = !loops && (chunkStart + AVAudioFramePosition(count) >= totalFrames)
    streamNextFrame = chunkStart + AVAudioFramePosition(count)

    let callbackType: AVAudioPlayerNodeCompletionCallbackType =
      isLastChunk ? .dataPlayedBack : .dataConsumed

    node.scheduleSegment(
      file, startingFrame: chunkStart, frameCount: count, at: nil,
      completionCallbackType: callbackType
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, generation == self.generation else { return }
        if isLastChunk {
          self.fireFinishedIfCurrent(generation)
        } else {
          self.scheduleNextStreamChunk(generation: generation)
        }
      }
    }
  }

  /// Captures position, then pauses. Order matters: read the timeline before
  /// pausing so a later resume continues from here.
  func pause() {
    lastKnownFrame = currentFrame
    if node.engine != nil {
      node.pause()
    }
    Logger.sounds.debug("SoundPlayer: paused at frame \(self.lastKnownFrame ?? 0)")
  }

  /// Stops playback and clears position. Bumps `generation` first so in-flight
  /// completions no-op before the reset; cancels any fade (its completion
  /// must not fire after a hard stop).
  func stop() {
    generation += 1
    fadeTimer?.invalidate()
    isFadingToSilence = false
    if node.engine != nil {
      node.stop()
    }
    segmentBaseFrame = 0
    lastKnownFrame = nil
  }

  /// Sets the position the next play(fromFrame: currentFrame) starts from.
  /// Clears any existing schedule, so callers must treat this as a stop.
  func seek(toFrame frame: AVAudioFramePosition) {
    let clamped = max(0, min(frame, max(totalFrames - 1, 0)))
    generation += 1
    fadeTimer?.invalidate()
    isFadingToSilence = false
    if node.engine != nil {
      node.stop()
    }
    segmentBaseFrame = clamped
    lastKnownFrame = clamped
  }

  /// Captures position for an engine rebuild. Safe while the engine is dying
  /// (playerTime nil falls back to the last memoized position).
  func freeze() {
    lastKnownFrame = currentFrame
  }

  // MARK: - Completion

  /// Fires the finished callback on main, fenced by `generation` so a stop()
  /// between scheduling and completion suppresses it.
  private func fireFinishedIfCurrent(_ generation: Int) {
    DispatchQueue.main.async { [weak self] in
      guard let self, generation == self.generation else { return }
      Logger.sounds.debug("SoundPlayer: playback finished")
      self.onPlaybackFinished?()
    }
  }
}
