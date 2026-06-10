//
//  AudioManager+SoloMode.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import Foundation
import os

extension AudioManager {
  // MARK: - Solo Mode

  /// The sound a `solo:` starred token refers to, or nil if the token isn't a
  /// solo token or its sound no longer exists. Single resolver shared by the
  /// picker, sidebar, CarPlay, and lock-screen navigation.
  func sound(forSoloToken token: String) -> Sound? {
    guard let fileName = GlobalSettings.soloFileName(fromToken: token) else { return nil }
    return sounds.first { $0.fileName == fileName }
  }

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

  /// Restore solo mode from persisted state if a solo sound was saved, playing
  /// only when `autoPlayOnLaunch` is set. Returns true when the saved solo
  /// "wins" (so launch shouldn't fall back to the preset): it's restored, or
  /// it's still pending a not-yet-loaded custom sound. Returns false when there
  /// is no saved solo, or — once `soundsFullyLoaded` is true — when the saved
  /// sound no longer exists (deleted); in that case the stale state is cleared.
  /// Idempotent: no-ops once that sound is already soloing.
  @MainActor
  @discardableResult
  func restoreSoloModeIfNeeded(soundsFullyLoaded: Bool = false) -> Bool {
    guard let savedSoloFileName = GlobalSettings.shared.getSavedSoloModeFileName() else {
      return false
    }
    if soloModeSound?.fileName == savedSoloFileName { return true }
    if let soloSound = sounds.first(where: { $0.fileName == savedSoloFileName }) {
      Logger.audio.debug("AudioManager: Restoring solo mode for '\(soloSound.title)'")
      enterSoloMode(for: soloSound, startPlaying: GlobalSettings.shared.autoPlayOnLaunch)
      return true
    }
    if soundsFullyLoaded {
      // Every sound is loaded and it still isn't found → it was deleted. Clear
      // the stale solo so launch falls back to the preset instead of silence.
      Logger.audio.debug("AudioManager: Saved solo sound '\(savedSoloFileName)' is gone; clearing")
      GlobalSettings.shared.saveSoloModeSound(fileName: nil)
      return false
    }
    Logger.audio.debug(
      "AudioManager: Solo sound '\(savedSoloFileName)' not loaded yet; deferring restore")
    return true
  }

  /// Apply the launch playback state for a preset (no solo): start playback when
  /// `autoPlayOnLaunch` is set and the preset has selected sounds, otherwise
  /// publish a paused Now Playing. Shared by initial launch and the fallback
  /// when a saved solo sound turns out to be missing.
  @MainActor
  func applyPresetLaunchState() {
    let preset = PresetManager.shared.currentPreset
    if GlobalSettings.shared.autoPlayOnLaunch, sounds.contains(where: { $0.isSelected }) {
      isGloballyPlaying = true
      playSelected()
      nowPlayingManager.updateInfo(
        preset: preset, presetName: preset?.name, creatorName: preset?.creatorName,
        artworkId: preset?.artworkId, isPlaying: true)
    } else {
      isGloballyPlaying = false
      nowPlayingManager.updateInfo(
        preset: preset, presetName: preset?.name, creatorName: preset?.creatorName,
        artworkId: preset?.artworkId, isPlaying: false)
    }
  }

  @MainActor
  func enterSoloMode(for sound: Sound, startPlaying: Bool = true) {
    // Already soloing this exact sound: do nothing. Re-running would save the
    // solo volume (1.0) as the "original", corrupting later restoration.
    if soloModeSound?.id == sound.id { return }

    Logger.audio.debug("AudioManager: Entering solo mode for '\(sound.title)'")

    // Solo and Quick Mix are mutually exclusive; leave Quick Mix first.
    if isQuickMix {
      exitQuickMix()
    }

    // Spatial sessions are bound to the preset mix; soloing ends them.
    if SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }

    // Switching directly from another solo sound: restore that sound's pre-solo
    // volume & selection first, so it doesn't stay selected at full volume and
    // leak into the mix the next time playback starts.
    restoreSoloSoundState()

    // Save original state before modifying
    soloModeOriginalVolume = sound.volume
    soloModeOriginalSelection = sound.isSelected

    // Stop all sounds but DON'T touch their selection state (preserve preset configuration)
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

    // Ensure the sound is loaded (loading applies a random start position)
    if !sound.isLoaded {
      sound.loadSound()
    } else if !sound.isPlaying {
      // Re-randomize a reused stopped player; auto-play no longer does this.
      sound.resetSoundPosition()
    }

    // Start playing unless we're restoring into a paused state (e.g. launch
    // with auto-play off). The sound is already selected, so the play/pause
    // control can resume it later.
    if startPlaying {
      setGlobalPlaybackState(true)
      sound.play()
    } else {
      isGloballyPlaying = false
    }

    // Update Now Playing info immediately
    nowPlayingManager.updateInfo(
      presetName: sound.title,
      isPlaying: startPlaying
    )
  }

  /// Restore the currently-soloed sound to its pre-solo volume & selection and
  /// clear the saved slots. Pauses the sound, but does not change global
  /// playback or clear `soloModeSound` — callers handle those.
  @MainActor
  private func restoreSoloSoundState() {
    guard let soloSound = soloModeSound else { return }

    soloSound.pause()

    if let originalVolume = soloModeOriginalVolume {
      soloSound.volume = originalVolume
      soloModeOriginalVolume = nil
    }

    if let originalSelection = soloModeOriginalSelection {
      soloSound.isSelected = originalSelection
      soloModeOriginalSelection = nil
    }
  }

  @MainActor
  func exitSoloMode() {
    guard soloModeSound != nil else { return }
    Logger.audio.debug("AudioManager: Exiting solo mode")

    restoreSoloSoundState()

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Stop global playback
    setGlobalPlaybackState(false)

    // A solo restored at launch skips the preset's applySoundStates, so
    // presetStatesApplied never flips and later mix edits won't persist.
    // Playback is already stopped above, so re-syncing here can't auto-start
    // audio (the isSelected didSet autoplay is gated on isGloballyPlaying); it
    // only corrects selection/volume to the preset and sets the flag.
    if !PresetManager.shared.presetStatesApplied,
      let preset = PresetManager.shared.currentPreset
    {
      PresetManager.shared.applySoundStates(preset.soundStates)
    }

    // Update media control command state
    updateNextPreviousCommandState()

    // Clear Now Playing info
    nowPlayingManager.updateInfo(
      presetName: "Blankie",
      isPlaying: false
    )

    Logger.audio.debug("AudioManager: Exit solo mode complete")
  }

  @MainActor
  func exitSoloModeWithoutResuming() {
    guard soloModeSound != nil else { return }
    Logger.audio.debug("AudioManager: Exiting solo mode (without resuming)")

    restoreSoloSoundState()

    // Clear solo mode
    soloModeSound = nil

    // Clear from persistent storage
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Update media control command state
    updateNextPreviousCommandState()

    Logger.audio.debug("AudioManager: Exit solo mode (without resuming) complete")
  }

  // MARK: - Preview Mode (for SoundSheet previews)

  @MainActor
  func enterPreviewMode(for sound: Sound) {
    Logger.audio.debug("AudioManager: Entering preview mode for '\(sound.title)'")

    // Store original volume and playback states (don't touch selection states)
    previewModeOriginalStates.removeAll()
    for existingSound in sounds {
      previewModeOriginalStates[existingSound.fileName] = PreviewOriginalState(
        volume: existingSound.volume,
        isPlaying: existingSound.isPlaying
      )
    }

    // Pause all other sounds (but preserve their playback position)
    // Don't pause the preview sound itself
    for otherSound in sounds where otherSound.id != sound.id {
      if otherSound.isPlaying {
        otherSound.pause()
      }
    }

    // Set preview mode (this doesn't trigger UI changes like solo mode)
    previewModeSound = sound

    // Set the sound to full volume for preview (will be adjusted by customization)
    sound.volume = 1.0

    // Ensure the sound is loaded
    if !sound.isLoaded {
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

    Logger.audio.debug("AudioManager: Preview mode started for '\(sound.title)'")
  }

  @MainActor
  func exitPreviewMode() {
    guard let previewSound = previewModeSound else { return }
    Logger.audio.debug("AudioManager: Exiting preview mode for '\(previewSound.title)'")

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

        // Restore playback state: if it was playing before and should still be
        // playing. isSelected can flip mid-preview (e.g. the editor marking a
        // sound preset-only deselects it) — never resume a deselected sound.
        if originalState.isPlaying, isGloballyPlaying, sound.isSelected {
          if !sound.isPlaying {
            Logger.audio.debug(
              "AudioManager: Resuming '\(sound.title)' - was playing before preview")
            sound.play()
          } else {
            Logger.audio.debug("AudioManager: '\(sound.title)' already playing, continuing")
          }
        }
      }
    }

    // Clear preview mode
    previewModeSound = nil
    previewModeOriginalStates.removeAll()

    Logger.audio.debug("AudioManager: Preview mode exited")
  }
}
