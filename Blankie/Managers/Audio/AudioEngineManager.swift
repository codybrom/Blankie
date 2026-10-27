//
//  AudioEngineManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import AudioToolbox
import os

/// Owns the single shared `AVAudioEngine` and its graph. Every `SoundPlayer`
/// attaches its node + gain here, feeding `mainMixerNode`, which runs through
/// one peak limiter to the output. `ensureRunning()` is the only place the
/// engine is ever started, so start failures and retries live in one place.
///
/// Threading: call from the main thread (same contract as Sound/SoundPlayer).
/// Notification handlers hop to the main actor before calling in.
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

  /// Single mix-bus peak limiter between the main mixer and the output.
  private(set) var limiter: AVAudioUnitEffect

  /// Experimental 3D environment for spatial sounds (mono inputs only). It lives
  /// alongside the normal chain and feeds the same main mixer.
  private(set) var environment = AVAudioEnvironmentNode()
  private var environmentConnected = false

  /// Registered players keyed by identity. `Sound` owns removal via `detach`.
  /// An explicit registry lets rebuilds enumerate every node.
  private(set) var registered: [ObjectIdentifier: SoundPlayer] = [:]

  /// Set once the main mixer, limiter and output are wired.
  private var limiterConnected = false

  // Rebuild coalescing guards (used by the +Lifecycle extension).
  var isRebuilding = false
  var pendingRebuild = false

  // Start-retry backoff bookkeeping.
  private var startRetryCount = 0
  private let maxStartRetries = 5
  /// One retry in flight at a time. Every selected sound's play() reaches
  /// ensureRunning, and they share one retry budget.
  private var startRetryPending = false

  /// Starts the engine. Tests replace it to simulate a start failure.
  var startEngine: (AVAudioEngine) throws -> Void = { try $0.start() }

  /// Set by `AudioManager`: a media-services reset tears down every Sound's
  /// player (without touching selection) for lazy rebuild on next play.
  var onEngineReset: (() -> Void)?

  /// Config-change observer token, re-bound whenever the engine is recreated.
  var configObserver: NSObjectProtocol?

  private init() {
    limiter = Self.makeLimiter()
    engine.isAutoShutdownEnabled = true
    observeEngineNotifications()

    // Global volume and mix-with-others live on the main mixer. GlobalSettings'
    // setters call applyGlobalVolumeSettings(). This seeds the initial gain.
    applyGlobalVolumeSettings()
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
    // The fresh mixer defaults to 1.0, so reapply the user's global volume.
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

  /// Attaches a player and wires its chain (idempotent). Spatial players feed the
  /// environment (mono, HRTF-positioned). Others feed their gain node, then the
  /// main mixer in the file's format (the mixer converts sample rate).
  func attach(_ player: SoundPlayer) {
    let key = ObjectIdentifier(player)
    // Trust the registry only while the node is attached. A teardown can leave
    // a detached node with a stale entry, and playing a detached node crashes.
    if registered[key] != nil, player.node.engine != nil {
      return
    }

    if player.node.engine == nil {
      engine.attach(player.node)
    }
    connectPlayerChain(player)

    registered[key] = player
  }

  /// Wires (or re-wires after a rebuild) a player's output chain.
  func connectPlayerChain(_ player: SoundPlayer) {
    if player.isSpatial {
      // Buffered spatial sounds carry their mono fold. Streamed ones play a
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

  /// Wires the 3D environment into the main mixer once.
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

  /// Default ring slot from a stable djb2 hash of the name plus a Fibonacci mix
  /// (raw djb2 low bits cluster on shared file suffixes). Swift's Hashable is
  /// seeded per launch. Placements are 2D at ear height.
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

  /// Wires the main mixer through the limiter to the output once. A nil format
  /// lets each edge adopt the hardware format across sample-rate switches.
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
      try startEngine(engine)
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

  /// Pauses hardware I/O once nothing is rendering. The graph stays intact for
  /// `ensureRunning()`. A running engine makes iOS report playback even at rate 0.
  @discardableResult
  func pauseIfIdle() -> Bool {
    guard engine.isRunning else { return false }
    guard !registered.values.contains(where: { $0.isPlaying }) else { return false }

    pause()
    return true
  }

  /// Unconditionally pauses hardware I/O (the post-retry safety net when a
  /// player still claims to be rendering after a global pause).
  func pause() {
    guard engine.isRunning else { return }
    engine.pause()
    state = .paused
    Logger.audio.debug("AudioEngineManager: Paused engine")
  }

  /// Exponential backoff (0.25 · 2^n s, 5 tries). After the cap, reports the
  /// failure and leaves the app paused with controls alive.
  private func scheduleStartRetry() {
    guard !startRetryPending else { return }
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
    startRetryPending = true
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      self.startRetryPending = false
      // Gate on play intent. A pause in the meantime must not restart the engine,
      // and a rebuild may have restarted it without rescheduling the failed sound.
      guard AudioManager.shared.isGloballyPlaying else {
        // The user paused. The next play starts with a full budget.
        self.startRetryCount = 0
        return
      }
      // A recovered engine still needs the selection rescheduled, or the lock
      // screen shows rate 1.0 over silence. playSelected() skips playing sounds.
      if self.ensureRunning() {
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

  /// Recomputes the main-mixer gain. GlobalSettings' volume setters (the only
  /// writers) call this synchronously so the slider responds immediately.
  func applyGlobalVolumeSettings() {
    let settings = GlobalSettings.shared
    globalVolume =
      Float(settings.volume) * (settings.mixWithOthers ? Float(settings.volumeWithOtherAudio) : 1)
  }
}
