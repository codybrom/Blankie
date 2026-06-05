//
//  SoundPlayer.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
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

  /// Owner-set callback fired once when a non-looping sound finishes playback.
  var onPlaybackFinished: (() -> Void)?

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

  // MARK: - Init

  init(fileURL: URL, loops: Bool) throws {
    self.loops = loops
    let audioFile = try AVAudioFile(forReading: fileURL)
    self.file = audioFile

    let format = audioFile.processingFormat
    self.totalFrames = audioFile.length
    self.sampleRate = format.sampleRate

    self.node = AVAudioPlayerNode()
    self.gain = AVAudioUnitEQ(numberOfBands: 0)
    self.gain.globalGain = 0

    let duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
    if duration <= SoundPlayer.bufferThreshold,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(max(totalFrames, 1)))
    {
      try audioFile.read(into: buffer)
      self.mode = .buffered(buffer)
      Logger.sounds.debug(
        "SoundPlayer: Buffered '\(fileURL.lastPathComponent)' (\(duration)s)")
    } else {
      self.mode = .streaming
      Logger.sounds.debug(
        "SoundPlayer: Streaming '\(fileURL.lastPathComponent)' (\(duration)s)")
    }
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
    fadeLevel = max(0, min(level, 1))
    applyVolume()
  }

  /// Linearly ramps the fade layer at 30 steps/sec. Starting a new fade (or a
  /// stop/seek) cancels the previous one — its completion never fires.
  func fade(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
    fadeTimer?.invalidate()
    let clampedTarget = max(0, min(target, 1))
    guard duration > 0, abs(clampedTarget - fadeLevel) > 0.001 else {
      fadeLevel = clampedTarget
      applyVolume()
      completion?()
      return
    }

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
      let tail = AVAudioFrameCount(totalFrames - fromFrame)
      node.scheduleSegment(
        file, startingFrame: fromFrame, frameCount: tail, at: nil, completionHandler: nil)
    }
    node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
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
