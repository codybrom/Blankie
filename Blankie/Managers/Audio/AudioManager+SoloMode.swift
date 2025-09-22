//
//  AudioManager+SoloMode.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import Foundation

extension AudioManager {
  // MARK: - Solo Mode

  @MainActor
  func toggleSoloMode(for sound: Sound) {
    if soloModeSound?.id == sound.id {
      // Exit solo mode
      exitSoloMode()
    } else {
      // Enter solo mode
      enterSoloMode(for: sound)
    }
  }

  @MainActor
  func enterSoloMode(for sound: Sound) {
    print("🎵 AudioManager: Entering solo mode for '\(sound.title)'")

    // Check if the sound was already playing
    let wasPlaying = sound.isSelected && isGloballyPlaying

    // Save original state before modifying
    soloModeOriginalVolume = sound.volume
    soloModeOriginalSelection = sound.isSelected

    // Pause all OTHER sounds (not the one we're soloing)
    for otherSound in sounds where otherSound.id != sound.id {
      otherSound.pause()
    }

    // Set solo mode
    soloModeSound = sound

    // Save to persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: sound.fileName)

    // Update media control command state
    updateNextPreviousCommandState()

    // Set the sound to full volume for solo mode
    sound.volume = 1.0

    // Temporarily mark the sound as selected for solo mode playback
    sound.isSelected = true

    // Ensure the sound is loaded
    if sound.player == nil {
      sound.loadSound()
    }

    // Always ensure we're playing in solo mode
    setGlobalPlaybackState(true)

    // If the sound was already playing, keep it playing
    // Otherwise start it
    if wasPlaying {
      // Sound should already be playing, just ensure volume is updated
      sound.updateVolume()
    } else {
      // Start playing the solo sound
      sound.play()
    }

    // Update Now Playing info immediately
    nowPlayingManager.updateInfo(
      presetName: sound.title,
      isPlaying: true
    )
  }

  @MainActor
  func exitSoloMode() {
    guard let soloSound = soloModeSound else { return }
    print("🎵 AudioManager: Exiting solo mode for '\(soloSound.title)'")
    print("🎵 AudioManager: Global playing state: \(isGloballyPlaying)")

    // Check if we should keep playing after exiting solo mode
    let shouldKeepPlaying = isGloballyPlaying

    // Save the original selection state before clearing it
    let wasOriginallySelected = soloModeOriginalSelection ?? false

    // Check if the solo sound should continue playing after exit
    let soloShouldContinuePlaying = wasOriginallySelected && shouldKeepPlaying

    // Only pause the solo sound if it shouldn't continue playing
    if !soloShouldContinuePlaying {
      print("🎵 AudioManager: Pausing solo sound")
      soloSound.pause()
    } else {
      print("🎵 AudioManager: Solo sound will continue playing in normal mode")
    }

    // Restore original state
    if let originalVolume = soloModeOriginalVolume {
      print("🎵 AudioManager: Restoring original volume: \(originalVolume)")
      soloSound.volume = originalVolume
      soloModeOriginalVolume = nil
      // Update volume if sound is still playing
      if soloShouldContinuePlaying {
        soloSound.updateVolume()
      }
    }

    if let originalSelection = soloModeOriginalSelection {
      print("🎵 AudioManager: Restoring original selection: \(originalSelection)")
      soloSound.isSelected = originalSelection
      soloModeOriginalSelection = nil
    }

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Update media control command state
    updateNextPreviousCommandState()

    // Restore normal playback if we were playing
    if shouldKeepPlaying {
      print("🎵 AudioManager: Restoring playback for selected sounds")
      // Play all sounds that should be playing according to the preset
      for sound in sounds where sound.isSelected {
        // Skip the solo sound since it's already playing if it should be
        if sound.id == soloSound.id, soloShouldContinuePlaying {
          continue
        }
        sound.play()
      }
    } else {
      print("🎵 AudioManager: Global playback is paused, keeping all sounds paused")
    }

    // Update Now Playing info with full preset details
    let currentPreset = PresetManager.shared.currentPreset
    nowPlayingManager.updateInfo(
      presetName: currentPreset?.name,
      creatorName: currentPreset?.creatorName,
      artworkId: currentPreset?.artworkId,
      isPlaying: isGloballyPlaying
    )

    print("🎵 AudioManager: Exit solo mode complete")
  }

  @MainActor
  func exitSoloModeWithoutResuming() {
    guard let soloSound = soloModeSound else { return }
    print("🎵 AudioManager: Exiting solo mode (without resuming) for '\(soloSound.title)'")

    // Pause the solo sound
    soloSound.pause()

    // Restore original state
    if let originalVolume = soloModeOriginalVolume {
      soloSound.volume = originalVolume
      soloModeOriginalVolume = nil
    }

    if let originalSelection = soloModeOriginalSelection {
      // Don't restore selection for non-Quick Mix sounds when in CarPlay Quick Mix mode
      if isQuickMix {
        #if CARPLAY_ENABLED
          let quickMixSounds = CarPlayInterfaceController.shared.quickMixSoundFileNames
        #else
          let quickMixSounds = [
            "rain", "waves", "fireplace", "white-noise",
            "wind", "stream", "birds", "coffee-shop",
          ]
        #endif
        if quickMixSounds.contains(soloSound.fileName) {
          soloSound.isSelected = originalSelection
        } else {
          soloSound.isSelected = false
        }
      } else {
        soloSound.isSelected = originalSelection
      }
      soloModeOriginalSelection = nil
    }

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Update media control command state
    updateNextPreviousCommandState()

    print("🎵 AudioManager: Exit solo mode (without resuming) complete")
  }

  // MARK: - Preview Mode (for SoundSheet previews)

  @MainActor
  func enterPreviewMode(for sound: Sound) {
    print("🎵 AudioManager: Entering preview mode for '\(sound.title)'")

    // Store original volume and playback states (don't touch selection states)
    previewModeOriginalStates.removeAll()
    for existingSound in sounds {
      previewModeOriginalStates[existingSound.fileName] = PreviewOriginalState(
        volume: existingSound.volume,
        isPlaying: existingSound.player?.isPlaying == true
      )
    }

    // Pause all other sounds (but preserve their playback position)
    // Don't pause the preview sound itself
    for otherSound in sounds where otherSound.id != sound.id {
      if otherSound.player?.isPlaying == true {
        otherSound.pause()
      }
    }

    // Set preview mode (this doesn't trigger UI changes like solo mode)
    previewModeSound = sound

    // Set the sound to full volume for preview (will be adjusted by customization)
    sound.volume = 1.0

    // Ensure the sound is loaded
    if sound.player == nil {
      sound.loadSound()
    }

    // Update volume based on any temporary customizations that might be applied
    sound.updateVolume()

    // Start playing the preview sound
    let wasAlreadyPlaying = previewModeOriginalStates[sound.fileName]?.isPlaying ?? false
    if !wasAlreadyPlaying {
      // Sound wasn't playing before - reset position (respecting randomization)
      sound.resetSoundPosition()
    }
    // Play the sound (continues from current position if it was already playing)
    sound.play()

    print("🎵 AudioManager: Preview mode started for '\(sound.title)'")
  }

  @MainActor
  func exitPreviewMode() {
    guard let previewSound = previewModeSound else { return }
    print("🎵 AudioManager: Exiting preview mode for '\(previewSound.title)'")

    // Handle the preview sound: pause it only if it wasn't playing before preview
    let previewSoundWasPlaying =
      previewModeOriginalStates[previewSound.fileName]?.isPlaying ?? false
    if !previewSoundWasPlaying {
      previewSound.pause()
    }
    // If it was playing before, let it continue playing (it will be handled in the restoration loop)

    // Restore original volume and playback states for all sounds
    for sound in sounds {
      if let originalState = previewModeOriginalStates[sound.fileName] {
        sound.volume = originalState.volume

        // Update volume to reflect the restored state
        sound.updateVolume()

        // Restore playback state: if it was playing before and should still be playing
        if originalState.isPlaying, isGloballyPlaying {
          if sound.player?.isPlaying != true {
            print("🎵 AudioManager: Resuming '\(sound.title)' - was playing before preview")
            sound.play()
          } else {
            print("🎵 AudioManager: '\(sound.title)' already playing, continuing")
          }
        }
      }
    }

    // Clear preview mode
    previewModeSound = nil
    previewModeOriginalStates.removeAll()

    print("🎵 AudioManager: Preview mode exited")
  }
}
