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
  /// current engine object. The handler hops to the main actor — never tear
  /// down the graph on AVFoundation's internal delivery queue (deadlock).
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
  /// every player's position before stopping, reconnects the graph, and — only
  /// if playback intent was active — restarts and resumes from frozen frames.
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

    // Snapshot positions: freeze() strictly BEFORE node.stop() (stop zeroes
    // the player timeline). Record who was playing for the resume pass.
    var resumeFrames: [ObjectIdentifier: AVAudioFramePosition] = [:]
    for (key, player) in registered {
      player.freeze()
      if player.isPlaying {
        resumeFrames[key] = player.currentFrame
      }
    }

    // Stop all, then re-establish per-sound edges and the mix-bus chain.
    for (_, player) in registered {
      player.stop()
      let format = player.file.processingFormat
      engine.connect(player.node, to: player.gain, format: format)
      engine.connect(player.gain, to: engine.mainMixerNode, format: format)
    }
    resetLimiterConnection()
    connectLimiterChainIfNeeded()

    if wasPlaying, ensureRunning() {
      for (key, player) in registered {
        guard let frame = resumeFrames[key] else { continue }
        player.play(fromFrame: frame)
      }
      // Reapply per-sound volumes (no-ops for sounds without a live player).
      for sound in AudioManager.shared.sounds {
        sound.updateVolume()
      }
    }

    finishRebuild(wasPlaying: wasPlaying)
  }

  /// Closes out a rebuild; if another change arrived mid-flight, runs exactly
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
    /// rebuild on next play. Never auto-resumes — Apple requires user action.
    func handleMediaServicesReset() {
      Logger.audio.error("AudioEngineManager: Media services reset — rebuilding engine")

      recreateEngine()

      AudioSessionManager.shared.reapplyConfiguration(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isCarPlayConnected: AudioManager.shared.isCarPlayConnected
      )

      // Tear down every Sound's player without touching selection; the next
      // play call rebuilds fresh SoundPlayers against the new engine.
      onEngineReset?()

      state = .paused
      Task { @MainActor in
        AudioManager.shared.setGlobalPlaybackState(false)
      }
    }
  #endif
}
