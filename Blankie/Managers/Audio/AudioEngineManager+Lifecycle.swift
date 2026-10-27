//
//  AudioEngineManager+Lifecycle.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import os

// MARK: - Configuration change & media-services recovery

extension AudioEngineManager {

  /// Registers (or re-binds) the configuration-change observer scoped to the
  /// current engine object. The handler hops to the main actor because tearing
  /// down the graph on AVFoundation's delivery queue deadlocks.
  func observeEngineNotifications() {
    if let existing = configObserver {
      NotificationCenter.default.removeObserver(existing)
      configObserver = nil
    }

    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleConfigurationChange()
      }
    }
  }

  /// Coalesced graph rebuild after a hardware configuration change. Freezes
  /// every player's position before stopping, reconnects the graph, and
  /// resumes from the frozen frames only if playback intent was active.
  func handleConfigurationChange() {
    // Coalesce bursts (CarPlay attach) into a single trailing rebuild.
    if isRebuilding {
      pendingRebuild = true
      return
    }
    isRebuilding = true

    // Playback intent from the app's global flag, not engine.isRunning (the
    // engine already stopped itself by the time this runs).
    let wasPlaying = AudioManager.shared.isGloballyPlaying
    state = .rebuilding

    Logger.audio.debug(
      "AudioEngineManager: Configuration change (wasPlaying: \(wasPlaying))")

    // freeze() must run before node.stop(), which zeroes the player timeline.
    // Players mid-fade-to-silence are logically paused, so they don't resume.
    var resumeFrames: [ObjectIdentifier: AVAudioFramePosition] = [:]
    var frozenFrames: [ObjectIdentifier: AVAudioFramePosition] = [:]
    for (key, player) in registered {
      player.freeze()
      // Capture every position: stop() clears it, and paused sounds continue
      // from here on the next play.
      frozenFrames[key] = player.currentFrame
      if player.isPlaying, !player.isFadingToSilence {
        resumeFrames[key] = player.currentFrame
      }
    }

    // Stop all, then re-establish per-sound edges and the mix-bus chains.
    resetEnvironmentConnection()
    for (_, player) in registered {
      player.stop()
      connectPlayerChain(player)
    }
    resetLimiterConnection()
    connectLimiterChainIfNeeded()

    if wasPlaying, ensureRunning() {
      for (key, player) in registered {
        guard let frame = resumeFrames[key] else { continue }
        player.play(fromFrame: frame)
        // A mid-fade-in player keeps its partial fadeLevel across the rebuild,
        // so snap it to full before updateVolume() reads it.
        player.setFadeLevel(1)
      }
      // Reapply per-sound volumes (no-ops for sounds without a live player).
      for sound in AudioManager.shared.sounds {
        sound.updateVolume()
      }
    }

    // Restore position for players we didn't resume (paused, or app globally
    // paused) so a later play continues where they left off.
    for (key, player) in registered where resumeFrames[key] == nil {
      if let frame = frozenFrames[key] {
        player.seek(toFrame: frame)
      }
    }

    finishRebuild(wasPlaying: wasPlaying)
  }

  /// Closes out a rebuild. If another change arrived mid-flight, runs exactly
  /// one more coalesced pass to capture the final hardware state.
  private func finishRebuild(wasPlaying: Bool) {
    isRebuilding = false
    state = wasPlaying ? .running : .paused

    if pendingRebuild {
      pendingRebuild = false
      handleConfigurationChange()
    }
  }

  #if os(iOS) || os(visionOS)
    /// Recovers from a media-services reset: the old engine and every node
    /// bound to it are dead. Recreates the engine, reapplies session config,
    /// and tears down each Sound's player (via `onEngineReset`) for lazy
    /// rebuild on next play. Never auto-resumes: Apple requires user action.
    func handleMediaServicesReset() {
      Logger.audio.error("AudioEngineManager: Media services reset — rebuilding engine")

      recreateEngine()

      AudioSessionManager.shared.reapplyConfiguration(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isCarPlayConnected: AudioManager.shared.isCarPlayConnected
      )

      // Tear down every Sound's player without touching selection. The next
      // play call rebuilds fresh SoundPlayers against the new engine.
      onEngineReset?()

      state = .paused
      // Clear pending interruption recovery too. A late interruption-ended
      // notification must not restart playback after the media server reset.
      AudioManager.shared.setGlobalPlaybackState(false, pauseFadeDuration: 0)
    }
  #endif
}
