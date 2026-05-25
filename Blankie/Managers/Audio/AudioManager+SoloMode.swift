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
    debugLog("🎵 AudioManager: Entering solo mode for '\(sound.title)'")

    // Save original state before modifying
    soloModeOriginalVolume = sound.volume
    soloModeOriginalSelection = sound.isSelected

    // Stop all sounds but DON'T touch their selection state (preserve preset configuration)
    for otherSound in sounds {
      if otherSound.id != sound.id {
        otherSound.pause()
      }
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

    // Start playing the solo sound
    sound.play()

    // Update Now Playing info immediately
    nowPlayingManager.updateInfo(
      presetName: sound.title,
      isPlaying: true
    )
  }

  @MainActor
  func exitSoloMode() {
    guard let soloSound = soloModeSound else { return }
    debugLog("🎵 AudioManager: Exiting solo mode for '\(soloSound.title)'")

    // Stop the solo sound
    soloSound.pause()

    // Restore original volume
    if let originalVolume = soloModeOriginalVolume {
      soloSound.volume = originalVolume
      soloModeOriginalVolume = nil
    }

    // Restore original selection state
    if let originalSelection = soloModeOriginalSelection {
      soloSound.isSelected = originalSelection
      soloModeOriginalSelection = nil
    }

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Stop global playback
    setGlobalPlaybackState(false)

    // Update media control command state
    updateNextPreviousCommandState()

    // Clear Now Playing info
    nowPlayingManager.updateInfo(
      presetName: "Blankie",
      isPlaying: false
    )

    debugLog("🎵 AudioManager: Exit solo mode complete")
  }

  @MainActor
  func exitSoloModeWithoutResuming() {
    guard let soloSound = soloModeSound else { return }
    debugLog("🎵 AudioManager: Exiting solo mode (without resuming) for '\(soloSound.title)'")

    // Pause the solo sound
    soloSound.pause()

    // Restore original volume
    if let originalVolume = soloModeOriginalVolume {
      soloSound.volume = originalVolume
      soloModeOriginalVolume = nil
    }

    // Restore original selection state
    if let originalSelection = soloModeOriginalSelection {
      soloSound.isSelected = originalSelection
      soloModeOriginalSelection = nil
    }

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Update media control command state
    updateNextPreviousCommandState()

    debugLog("🎵 AudioManager: Exit solo mode (without resuming) complete")
  }

  // MARK: - Preview Mode (for SoundSheet previews)

  @MainActor
  func enterPreviewMode(for sound: Sound) {
    debugLog("🎵 AudioManager: Entering preview mode for '\(sound.title)'")

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

    debugLog("🎵 AudioManager: Preview mode started for '\(sound.title)'")
  }

  @MainActor
  func exitPreviewMode() {
    guard let previewSound = previewModeSound else { return }
    debugLog("🎵 AudioManager: Exiting preview mode for '\(previewSound.title)'")

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
            debugLog("🎵 AudioManager: Resuming '\(sound.title)' - was playing before preview")
            sound.play()
          } else {
            debugLog("🎵 AudioManager: '\(sound.title)' already playing, continuing")
          }
        }
      }
    }

    // Clear preview mode
    previewModeSound = nil
    previewModeOriginalStates.removeAll()

    debugLog("🎵 AudioManager: Preview mode exited")
  }
}
