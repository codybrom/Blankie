//
//  AudioManager+QuickMix.swift
//  Blankie
//
//  Created by Cody Bromley on 6/7/25.
//

import Foundation
import os

extension AudioManager {
  // MARK: - Quick Mix Mode

  @MainActor
  func enterQuickMix(with initialSounds: [Sound] = []) {
    Logger.audio.debug("AudioManager: Entering Quick Mix mode")

    // Exit solo mode if active
    if soloModeSound != nil {
      exitSoloModeWithoutResuming()
    }

    // Save current preset before clearing
    preQuickMixPreset = PresetManager.shared.currentPreset

    // Clear any current preset
    PresetManager.shared.clearCurrentPreset()

    // Spatial sessions are bound to the preset mix; Quick Mix ends them.
    if SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }

    // Save original states of all sounds
    quickMixOriginalStates = sounds.map { sound in
      QuickMixState(sound: sound, isSelected: sound.isSelected, volume: sound.volume)
    }

    // Fade all sounds out first (entering Quick Mix reads as a crossfade)
    for sound in sounds {
      sound.pause()
      sound.isSelected = false
    }

    // Set Quick Mix mode
    isQuickMix = true

    // Update media control command state
    updateNextPreviousCommandState()

    // Filter initial sounds to only include Quick Mix sounds (built-in only)
    let quickMixSounds = GlobalSettings.shared.quickMixSoundFileNames
    let validInitialSounds = initialSounds.filter { sound in
      quickMixSounds.contains(sound.fileName) && !sound.isCustom
    }

    Logger.audio.debug(
      "AudioManager: Filtered \(initialSounds.count) initial sounds to \(validInitialSounds.count) valid Quick Mix sounds"
    )

    // Reset all Quick Mix sounds to 80% volume
    for sound in sounds where quickMixSounds.contains(sound.fileName) && !sound.isCustom {
      sound.volume = 0.8
      Logger.audio.debug("AudioManager: Reset \(sound.fileName) volume to 80%")
    }

    // Enable only the valid initial sounds
    for sound in validInitialSounds {
      sound.isSelected = true
      sound.play()
    }

    // Update playback state
    let hasActiveSounds = sounds.contains { $0.isSelected && $0.isPlaying }
    setGlobalPlaybackState(hasActiveSounds)

    // Update Now Playing info
    nowPlayingManager.updateInfo(
      presetName: "Quick Mix",
      isPlaying: hasActiveSounds
    )
  }

  @MainActor
  func exitQuickMix() {
    guard isQuickMix else { return }
    Logger.audio.debug("AudioManager: Exiting Quick Mix mode")

    // Pause all current sounds
    for sound in sounds {
      sound.pause()
    }

    // Restore original states
    for state in quickMixOriginalStates {
      state.sound.isSelected = state.isSelected
      state.sound.volume = state.volume

      // Resume playing if it was selected before
      if state.isSelected, isGloballyPlaying {
        state.sound.play()
      }
    }

    // Clear the saved states
    quickMixOriginalStates = []

    // Exit Quick Mix mode
    isQuickMix = false

    // Update media control command state
    updateNextPreviousCommandState()

    // Restore the previous preset if it exists
    if let savedPreset = preQuickMixPreset {
      Logger.audio.debug("AudioManager: Restoring previous preset: '\(savedPreset.name)'")
      PresetManager.shared.setCurrentPreset(savedPreset)

      // Update Now Playing info with restored preset
      nowPlayingManager.updateInfo(
        preset: savedPreset,
        presetName: savedPreset.name,
        creatorName: savedPreset.creatorName,
        artworkId: savedPreset.artworkId,
        isPlaying: isGloballyPlaying
      )
    } else {
      // No previous preset, just update with current state
      nowPlayingManager.updateInfo(
        presetName: nil,
        creatorName: nil,
        isPlaying: isGloballyPlaying
      )
    }

    // Clear the saved preset
    preQuickMixPreset = nil
  }

  @MainActor
  func toggleQuickMixSound(_ sound: Sound) {
    guard isQuickMix else { return }

    // Only allow toggling of built-in sounds (no custom sounds)
    guard !sound.isCustom else {
      Logger.audio.debug(
        "AudioManager: Attempted to toggle custom sound in Quick Mix: \(sound.fileName)")
      return
    }

    if sound.isSelected {
      sound.isSelected = false
      sound.pause()
    } else {
      sound.isSelected = true
      sound.play()
    }

    // Update playback state
    let hasActiveSounds = sounds.contains { $0.isSelected && $0.isPlaying }
    setGlobalPlaybackState(hasActiveSounds)

    // Update Now Playing info
    nowPlayingManager.updateInfo(
      presetName: "Quick Mix",
      isPlaying: hasActiveSounds
    )
  }
}
