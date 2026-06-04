//
//  AudioManager+PlaybackControl.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import AVFoundation
import Foundation
import SwiftUI

extension AudioManager {
  /// Toggles the playback state of all selected sounds
  @MainActor func togglePlayback() {
    setGlobalPlaybackState(!isGloballyPlaying)
  }

  @MainActor
  func resetSounds() {
    debugLog("AudioManager: Resetting all sounds")

    // First pause all sounds immediately
    for sound in sounds {
      debugLog("  - Stopping '\(sound.fileName)'")
      sound.pause(immediate: true)
    }
    setGlobalPlaybackState(false)
    // Reset all sounds
    for sound in sounds {
      sound.volume = 0.75
      sound.isSelected = false
    }
    // Reset "All Sounds" volume
    GlobalSettings.shared.setVolume(1.0)

    // Update hasSelectedSounds after resetting
    updateHasSelectedSounds()

    // Call the reset callback
    onReset?()
    debugLog("AudioManager: Reset complete")
  }

  public func updateNowPlayingInfoForPreset(
    preset: Preset? = nil,
    presetName: String? = nil,
    creatorName: String? = nil,
    artworkId: UUID? = nil
  ) {
    Task { @MainActor in
      nowPlayingManager.updateInfo(
        preset: preset,
        presetName: presetName,
        creatorName: creatorName,
        artworkId: artworkId,
        isPlaying: isGloballyPlaying
      )
    }
  }

  func updateNowPlayingState() {
    Task { @MainActor in
      nowPlayingManager.updatePlaybackState(isPlaying: isGloballyPlaying)
    }
  }

  func setPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    Task { @MainActor [weak self] in
      guard let self = self else { return }

      guard !self.isInitializing || forceUpdate else {
        debugLog("AudioManager: Ignoring setPlaybackState during initialization")
        return
      }

      if self.isGloballyPlaying != playing {
        debugLog(
          "AudioManager: Setting playback state to \(playing) - Current global state: \(self.isGloballyPlaying)"
        )
        self.isGloballyPlaying = playing

        if playing {
          self.playSelected()
        } else {
          self.pauseAll()
        }
        let currentPreset = PresetManager.shared.currentPreset
        self.nowPlayingManager.updateInfo(
          preset: currentPreset,
          presetName: currentPreset?.name,
          creatorName: currentPreset?.creatorName,
          artworkId: currentPreset?.artworkId,
          isPlaying: playing
        )
      } else {
        debugLog(
          "AudioManager: setPlaybackState called, but state is the same \(playing), ignoring")
      }
    }
  }

  func playSelected() {
    debugLog("AudioManager: Playing selected sounds")
    guard isGloballyPlaying else {
      debugLog("AudioManager: Not playing sounds because global playback is disabled")
      return
    }

    #if os(iOS) || os(visionOS)
      // Setup audio session when starting playback
      setupAudioSessionForPlayback()
      // Setup audio session observers on first playback
      setupAudioSessionObservers()
    #endif

    // If in solo mode, play only the solo sound
    if let soloSound = soloModeSound {
      debugLog("  - In solo mode, playing only '\(soloSound.fileName)'")

      // Play the solo sound at its current volume
      soloSound.play()

      // Update Now Playing info for solo mode
      Task { @MainActor in
        nowPlayingManager.updateInfo(
          presetName: soloSound.title,
          isPlaying: true
        )
      }
      return
    }

    // Normal mode: play all selected sounds according to preset
    for sound in sounds where sound.isSelected {
      // Check if this sound is starting fresh (not paused or playing)
      let wasPlaying = sound.player?.isPlaying == true
      let currentTime = sound.player?.currentTime ?? 0
      let duration = sound.player?.duration ?? 0
      let isPaused = sound.player != nil && !wasPlaying && currentTime > 0 && currentTime < duration

      if !wasPlaying, !isPaused {
        // Sound is truly stopped/new/finished, reset position (respecting randomization)
        sound.resetSoundPosition()
      }

      sound.play()
    }

    // Update Now Playing info with full preset details
    Task { @MainActor in
      let currentPreset = PresetManager.shared.currentPreset
      self.nowPlayingManager.updateInfo(
        preset: currentPreset,
        presetName: currentPreset?.name,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId,
        isPlaying: true
      )
    }
  }

  func pauseAll() {
    debugLog("AudioManager: Pausing all selected sounds")

    for sound in sounds where sound.isSelected {
      sound.pause()
    }

    // Note: We intentionally do NOT deactivate the audio session here
    // This keeps the Now Playing controls visible on lock screen/control center
    // The session will be deactivated when appropriate (background, termination, etc.)
  }

  @MainActor
  public func setGlobalPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    guard !isInitializing || forceUpdate else {
      debugLog("AudioManager: Ignoring setPlaybackState during initialization")
      return
    }

    debugLog(
      "AudioManager: Setting playback state to \(playing) - Current global state: \(isGloballyPlaying)"
    )

    // Update state first
    isGloballyPlaying = playing

    // Then handle playback
    if playing {
      playSelected()
    } else {
      pauseAll()
    }

    // Always update Now Playing info with full preset details
    if let soloSound = soloModeSound {
      // In solo mode, just show the sound title
      nowPlayingManager.updateInfo(
        presetName: soloSound.title,
        isPlaying: isGloballyPlaying
      )
    } else {
      // Normal mode - include full preset details
      let currentPreset = PresetManager.shared.currentPreset
      nowPlayingManager.updateInfo(
        preset: currentPreset,
        presetName: currentPreset?.name,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId,
        isPlaying: isGloballyPlaying
      )
    }
  }

  // MARK: - Update Playing Sounds

  func updatePlayingSounds() {
    // Stop any sounds that are playing but shouldn't be
    for sound in sounds {
      if !sound.isSelected, sound.player?.isPlaying == true {
        debugLog(
          "AudioManager: Stopping deselected sound '\(sound.fileName)' that was still playing")
        sound.pause(immediate: true)
      }
    }
  }
}
