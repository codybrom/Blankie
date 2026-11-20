//
//  EngineSoundPlayer.swift
//  Blankie
//
//  Created by Cody Bromley on 11/9/26.
//

import AVFoundation

/// What the engine and `Sound` need from a player. `SoundPlayer` plays files and
/// `KaleidoscopePlayer` synthesizes Kaleidoscopes live.
protocol EngineSoundPlayer: AnyObject {
  /// The node the engine attaches and feeds into `gain`.
  var engineNode: AVAudioNode { get }
  var gain: AVAudioUnitEQ { get }
  /// The format `engineNode` connects with.
  var connectionFormat: AVAudioFormat { get }
  var isSpatial: Bool { get }
  var isMonoSource: Bool { get }
  var isPlaying: Bool { get }
  var isFadingToSilence: Bool { get }
  var fadeLevel: Float { get }
  var currentFrame: AVAudioFramePosition { get }
  var currentTime: TimeInterval { get }
  var duration: TimeInterval { get }
  var loops: Bool { get }
  var totalFrames: AVAudioFramePosition { get }
  var sampleRate: Double { get }
  var volume: Float { get set }
  var onPlaybackFinished: (() -> Void)? { get set }
  func freeze()
  func stop()
  func pause()
  func play(fromFrame: AVAudioFramePosition)
  func seek(toFrame: AVAudioFramePosition)
  func setFadeLevel(_ level: Float)
  func setBoostDB(_ db: Float)
  func fade(to target: Float, duration: TimeInterval, completion: (() -> Void)?)
}

extension EngineSoundPlayer {
  func fade(to target: Float, duration: TimeInterval) {
    fade(to: target, duration: duration, completion: nil)
  }
}
