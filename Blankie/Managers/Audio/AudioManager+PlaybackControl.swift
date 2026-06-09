//
//  AudioManager+PlaybackControl.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import AVFoundation
import Foundation
import SwiftUI
import os

extension AudioManager {
  /// Toggles the playback state of all selected sounds
  @MainActor func togglePlayback() {
    setGlobalPlaybackState(!isGloballyPlaying)
  }

  @MainActor
  func resetSounds() {
    Logger.audio.debug("AudioManager: Resetting all sounds")

    // First pause all sounds immediately
    for sound in sounds {
      Logger.audio.debug("  - Stopping '\(sound.fileName)'")
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
    Logger.audio.debug("AudioManager: Reset complete")
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
        Logger.audio.debug("AudioManager: Ignoring setPlaybackState during initialization")
        return
      }

      if self.isGloballyPlaying != playing {
        Logger.audio.debug(
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
        Logger.audio.debug(
          "AudioManager: setPlaybackState called, but state is the same \(playing), ignoring")
      }
    }
  }

  func playSelected() {
    Logger.audio.debug("AudioManager: Playing selected sounds")
    guard isGloballyPlaying else {
      Logger.audio.debug("AudioManager: Not playing sounds because global playback is disabled")
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
      Logger.audio.debug("  - In solo mode, playing only '\(soloSound.fileName)'")

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
      // Resume paused sounds in place; reset stopped/new/finished ones
      // (respecting randomization). Explicit state replaces currentTime inference.
      if !sound.isPlaying, sound.playbackState != .paused {
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
    Logger.audio.debug("AudioManager: Pausing all selected sounds")

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
      Logger.audio.debug("AudioManager: Ignoring setPlaybackState during initialization")
      return
    }

    Logger.audio.debug(
      "AudioManager: Setting playback state to \(playing) - Current global state: \(self.isGloballyPlaying)"
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

  // MARK: - Music Exclusivity

  /// Enforces the one-music-per-preset rule: when `keep` is selected, every
  /// other selected music sound is deselected (fades out) so the mix holds at
  /// most one music sound at a time (last selected wins). Applies to Quick Mix
  /// too. No-op during preset apply / solo, which manage selection themselves.
  func deselectOtherMusicSounds(except keep: Sound) {
    guard soloModeSound == nil, !isApplyingPresetStates else { return }
    for sound in sounds where sound.id != keep.id && sound.isSelected && sound.isMusic {
      Logger.audio.debug(
        "AudioManager: Music '\(sound.fileName)' yields the slot to '\(keep.fileName)'")
      sound.isSelected = false
    }
  }

  // MARK: - Update Playing Sounds

  func updatePlayingSounds() {
    // Stop any sounds that are playing but shouldn't be. Sounds in a fade-out
    // (.paused mid-ramp) are already winding down — hard-stopping them would
    // kill the crossfade.
    for sound in sounds {
      if !sound.isSelected, sound.isPlaying, sound.playbackState == .playing {
        Logger.audio.debug(
          "AudioManager: Stopping deselected sound '\(sound.fileName)' that was still playing")
        sound.pause(immediate: true)
      }
    }
  }
}
