//
//  AudioEngineManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import AudioToolbox
import Combine
import os

/// Owns the single shared `AVAudioEngine` and its graph. Every `SoundPlayer`
/// attaches its node + gain here, feeding `mainMixerNode`, which runs through
/// one peak limiter to the output. `ensureRunning()` is the only place the
/// engine is ever started, so start failures and retries live in one place.
///
/// Threading: call from the main thread (same contract as Sound/SoundPlayer);
/// notification handlers hop to the main actor before calling in.
final class AudioEngineManager {
  static let shared = AudioEngineManager()

  private(set) var engine = AVAudioEngine()

  /// Lifecycle phases used by the configuration-change rebuild logic.
  enum EngineState {
    case idle
    case running
    case paused
    case rebuilding
    case failed(retryCount: Int)
  }

  /// `var` (not `private(set)`) because the +Lifecycle extension drives the
  /// rebuild transitions from another file (same relaxation as Sound.lufs).
  var state: EngineState = .idle

  /// Single mix-bus peak limiter (mainMixer → limiter → output).
  private(set) var limiter: AVAudioUnitEffect

  /// Experimental 3D environment for spatial sounds (mono inputs only); lives
  /// alongside the normal chain and feeds the same main mixer.
  private(set) var environment = AVAudioEnvironmentNode()
  private var environmentConnected = false

  /// Registered players keyed by identity. `Sound` owns removal via `detach`;
  /// an explicit registry lets rebuilds enumerate every node.
  private(set) var registered: [ObjectIdentifier: SoundPlayer] = [:]

  /// Set once the lazy mainMixer → limiter → output chain is wired up.
  private var limiterConnected = false

  // Rebuild coalescing guards (used by the +Lifecycle extension).
  var isRebuilding = false
  var pendingRebuild = false

  // Start-retry backoff bookkeeping.
  private var startRetryCount = 0
  private let maxStartRetries = 5

  /// Set by `AudioManager`: a media-services reset tears down every Sound's
  /// player (without touching selection) for lazy rebuild on next play.
  var onEngineReset: (() -> Void)?

  /// Config-change observer token, re-bound whenever the engine is recreated.
  var configObserver: NSObjectProtocol?

  private var settingsObservers = Set<AnyCancellable>()

  private init() {
    limiter = Self.makeLimiter()
    engine.isAutoShutdownEnabled = true
    observeEngineNotifications()

    // Global volume and mix-with-others apply to the whole mix, so they live
    // on the main mixer (per-sound updateVolume no longer multiplies them in).
    GlobalSettings.shared.$volume
      .combineLatest(
        GlobalSettings.shared.$mixWithOthers, GlobalSettings.shared.$volumeWithOtherAudio
      )
      .sink { [weak self] volume, mixWithOthers, volumeWithOthers in
        self?.globalVolume = Float(volume) * (mixWithOthers ? Float(volumeWithOthers) : 1)
      }
      .store(in: &settingsObservers)
  }

  /// Recreates the engine + limiter after a media-services reset.
  func recreateEngine() {
    registered.removeAll()
    limiterConnected = false
    environmentConnected = false
    engine = AVAudioEngine()
    engine.isAutoShutdownEnabled = true
    limiter = Self.makeLimiter()
    environment = AVAudioEnvironmentNode()
    observeEngineNotifications()
    // The fresh mixer defaults to 1.0; reapply the user's global volume.
    globalVolume =
      Float(GlobalSettings.shared.volume)
      * (GlobalSettings.shared.mixWithOthers
        ? Float(GlobalSettings.shared.volumeWithOtherAudio) : 1)
  }

  /// Builds the peak limiter audio unit from its component description.
  static func makeLimiter() -> AVAudioUnitEffect {
    var description = AudioComponentDescription()
    description.componentType = kAudioUnitType_Effect
    description.componentSubType = kAudioUnitSubType_PeakLimiter
    description.componentManufacturer = kAudioUnitManufacturer_Apple
    return AVAudioUnitEffect(audioComponentDescription: description)
  }

  // MARK: - Graph attach / detach

  /// Attaches a player and wires its chain: spatial players go node →
  /// environment (mono, HRTF-positioned); everything else node → gain →
  /// mainMixer with the file's format (the mixer handles SR conversion).
  /// Idempotent.
  func attach(_ player: SoundPlayer) {
    let key = ObjectIdentifier(player)
    guard registered[key] == nil else { return }

    engine.attach(player.node)
    connectPlayerChain(player)

    registered[key] = player
  }

  /// Wires (or re-wires after a rebuild) a player's output chain.
  func connectPlayerChain(_ player: SoundPlayer) {
    if player.isSpatial {
      // Buffered spatial sounds carry their mono fold; streamed ones play a
      // rendered mono cache, so the file's own format is already mono.
      let format: AVAudioFormat
      switch player.mode {
      case .buffered(let mono): format = mono.format
      case .streaming: format = player.file.processingFormat
      }
      connectEnvironmentIfNeeded()
      engine.connect(player.node, to: environment, format: format)
      player.node.renderingAlgorithm = .HRTFHQ
      player.node.position = player.spatialPosition ?? Self.spatialPosition(for: player.sourceName)
    } else {
      if player.gain.engine == nil {
        engine.attach(player.gain)
      }
      let format = player.file.processingFormat
      engine.connect(player.node, to: player.gain, format: format)
      engine.connect(player.gain, to: engine.mainMixerNode, format: format)
    }
  }

  /// Stops a player, disconnects and detaches its nodes, and forgets it.
  func detach(_ player: SoundPlayer) {
    let key = ObjectIdentifier(player)
    guard registered[key] != nil else { return }

    player.stop()
    engine.disconnectNodeOutput(player.node)
    engine.detach(player.node)
    if player.gain.engine != nil {
      engine.disconnectNodeOutput(player.gain)
      engine.detach(player.gain)
    }

    registered[key] = nil
  }

  // MARK: - Spatial environment

  /// Wires the 3D environment into the mix once (environment → mainMixer).
  func connectEnvironmentIfNeeded() {
    guard !environmentConnected else { return }

    if environment.engine == nil {
      engine.attach(environment)
    }
    engine.connect(environment, to: engine.mainMixerNode, format: nil)
    applyHeadTrackingSetting()
    environmentConnected = true
  }

  /// Applies the session's head-tracking mode to the live environment node
  /// (no-op without compatible AirPods + the head-pose entitlement).
  func applyHeadTrackingSetting() {
    #if !os(visionOS)
      environment.isListenerHeadTrackingEnabled =
        SpatialSessionManager.shared.mode == .headTracked
    #endif
  }

  /// Forces the environment chain to re-wire after a graph rebuild.
  func resetEnvironmentConnection() {
    environmentConnected = false
  }

  /// Converts a placement to engine coordinates (forward is -z, right is +x).
  static func point(angleDegrees: Float, distance: Float, elevation: Float = 0) -> AVAudio3DPoint {
    let radians = angleDegrees * .pi / 180
    return AVAudio3DPoint(
      x: distance * sin(radians), y: elevation, z: -distance * cos(radians))
  }

  /// Default ring slot from a stable hash of the sound's name (djb2, then a
  /// Fibonacci mix — raw djb2 low bits are dominated by the shared ".m4a" /
  /// ".wav" suffixes, which clustered every sound at nearly the same angle).
  /// Swift's Hashable is seeded per launch, hence the hand-rolled hash.
  /// Ear height only — placements are 2D throughout.
  static func defaultSpatialPlacement(for name: String) -> (
    angleDegrees: Float, distance: Float
  ) {
    var hash: UInt32 = 5381
    for byte in name.utf8 {
      hash = hash &* 33 &+ UInt32(byte)
    }
    hash = hash &* 2_654_435_761
    return (Float((hash >> 16) % 360), 2.0)
  }

  /// A stable default position around the listener for un-placed sounds.
  static func spatialPosition(for name: String) -> AVAudio3DPoint {
    let slot = defaultSpatialPlacement(for: name)
    return point(angleDegrees: slot.angleDegrees, distance: slot.distance)
  }

  // MARK: - Limiter chain

  /// Wires mainMixer → limiter → output once. Format nil lets each edge adopt
  /// the hardware format, so output sample-rate switches stay the engine's job.
  func connectLimiterChainIfNeeded() {
    guard !limiterConnected else { return }

    if limiter.engine == nil {
      engine.attach(limiter)
    }
    engine.connect(engine.mainMixerNode, to: limiter, format: nil)
    engine.connect(limiter, to: engine.outputNode, format: nil)

    limiterConnected = true
  }

  /// Forces the limiter chain to re-wire on the next ensureRunning() (used
  /// after a graph rebuild resets edges).
  func resetLimiterConnection() {
    limiterConnected = false
  }

  // MARK: - Engine start choke point

  /// The single place the engine is ever started. On failure, schedules a
  /// backoff retry and returns false so callers leave the app paused.
  @discardableResult
  func ensureRunning() -> Bool {
    if engine.isRunning {
      state = .running
      return true
    }

    connectLimiterChainIfNeeded()
    engine.prepare()

    do {
      try engine.start()
      startRetryCount = 0
      state = .running
      return true
    } catch {
      Logger.audio.error(
        "AudioEngineManager: Failed to start engine: \(error, privacy: .public)")
      scheduleStartRetry()
      return false
    }
  }

  /// Exponential backoff (0.25 · 2^n s, 5 tries); after the cap, reports the
  /// failure and leaves the app paused with controls alive.
  private func scheduleStartRetry() {
    guard startRetryCount < maxStartRetries else {
      Logger.audio.error(
        "AudioEngineManager: Engine start gave up after \(self.maxStartRetries, privacy: .public) retries"
      )
      state = .failed(retryCount: startRetryCount)
      startRetryCount = 0
      ErrorReporter.shared.report(AudioError.engineStartFailed)
      Task { @MainActor in
        AudioManager.shared.setGlobalPlaybackState(false)
      }
      return
    }

    let attempt = startRetryCount
    startRetryCount += 1
    state = .failed(retryCount: startRetryCount)

    let delay = 0.25 * pow(2.0, Double(attempt))
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !self.engine.isRunning else { return }
      // Recovering the engine isn't enough: if we were "playing" while it was
      // down, nothing rescheduled the sounds, so the lock screen shows rate 1.0
      // over silence. Resume the (solo-aware) selection once it's back.
      if self.ensureRunning(), AudioManager.shared.isGloballyPlaying {
        AudioManager.shared.playSelected()
      }
    }
  }

  // MARK: - Volume

  /// Master output volume on the main mixer (post-mix, pre-limiter).
  var globalVolume: Float {
    get { engine.mainMixerNode.outputVolume }
    set { engine.mainMixerNode.outputVolume = newValue }
  }
}
