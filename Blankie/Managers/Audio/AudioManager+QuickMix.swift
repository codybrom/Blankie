//
//  AudioManager+QuickMix.swift
//  Blankie
//
//  Created by Cody Bromley on 6/7/25.
//

import Foundation

extension AudioManager {
  // MARK: - Quick Mix Mode

  @MainActor
  func enterQuickMix(with initialSounds: [Sound] = []) {
    print("🚗 AudioManager: Entering Quick Mix mode")

    // Exit solo mode if active
    if soloModeSound != nil {
      exitSoloModeWithoutResuming()
    }

    // Save current preset before clearing
    preQuickMixPreset = PresetManager.shared.currentPreset

    // Clear any current preset
    PresetManager.shared.clearCurrentPreset()

    // Save original states of all sounds
    quickMixOriginalStates = sounds.map { sound in
      QuickMixState(sound: sound, isSelected: sound.isSelected, volume: sound.volume)
    }

    // Stop all sounds first
    for sound in sounds {
      sound.pause(immediate: true)
      sound.isSelected = false
    }

    // Set Quick Mix mode
    isQuickMix = true

    // Update media control command state
    updateNextPreviousCommandState()

    // Filter initial sounds to only include Quick Mix sounds (built-in only)
    #if CARPLAY_ENABLED
      let quickMixSounds = CarPlayInterfaceController.shared.quickMixSoundFileNames
    #else
      let quickMixSounds = GlobalSettings.shared.quickMixSoundFileNames
    #endif
    let validInitialSounds = initialSounds.filter { sound in
      quickMixSounds.contains(sound.fileName) && !sound.isCustom
    }

    print(
      "🚗 AudioManager: Filtered \(initialSounds.count) initial sounds to \(validInitialSounds.count) valid Quick Mix sounds"
    )

    // Reset all Quick Mix sounds to 80% volume
    for sound in sounds where quickMixSounds.contains(sound.fileName) && !sound.isCustom {
      sound.volume = 0.8
      print("🚗 AudioManager: Reset \(sound.fileName) volume to 80%")
    }

    // Enable only the valid initial sounds
    for sound in validInitialSounds {
      sound.isSelected = true
      sound.play()
    }

    // Update playback state
    let hasActiveSounds = sounds.contains { $0.isSelected && $0.player?.isPlaying == true }
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
    print("🚗 AudioManager: Exiting Quick Mix mode")

    // Pause all current sounds
    for sound in sounds {
      sound.pause()
    }

    // Restore original states
    for state in quickMixOriginalStates {
      state.sound.isSelected = state.isSelected
      state.sound.volume = state.volume

      // Resume playing if it was selected before
      if state.isSelected && isGloballyPlaying {
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
      print("🚗 AudioManager: Restoring previous preset: '\(savedPreset.name)'")
      PresetManager.shared.setCurrentPreset(savedPreset)

      // Update Now Playing info with restored preset
      nowPlayingManager.updateInfo(
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
      print("🚗 AudioManager: Attempted to toggle custom sound in Quick Mix: \(sound.fileName)")
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
    let hasActiveSounds = sounds.contains { $0.isSelected && $0.player?.isPlaying == true }
    setGlobalPlaybackState(hasActiveSounds)

    // Update Now Playing info
    nowPlayingManager.updateInfo(
      presetName: "Quick Mix",
      isPlaying: hasActiveSounds
    )
  }
}
