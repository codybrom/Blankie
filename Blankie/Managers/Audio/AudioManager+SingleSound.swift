//
//  AudioManager+SingleSound.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import Foundation
import os

extension AudioManager {
  // MARK: - Single Sound

  /// The sound a `solo:` starred token refers to, or nil if the token isn't a
  /// single sound token or its sound no longer exists.
  func sound(forSingleToken token: String) -> Sound? {
    guard let fileName = GlobalSettings.singleFileName(fromToken: token) else { return nil }
    return sounds.first { $0.fileName == fileName }
  }

  @MainActor
  func toggleSingleSound(for sound: Sound) {
    if singleSound?.id == sound.id {
      exitSingleSound()
    } else {
      enterSingleSound(for: sound)
    }
  }

  /// Restores a saved single sound, playing only when `autoPlayOnLaunch` is set.
  /// Returns true if the single sound was restored or its custom sound hasn't loaded yet
  /// (launch skips the preset). Once `soundsFullyLoaded`, a missing sound clears
  /// the saved single sound and returns false.
  @MainActor
  @discardableResult
  func restoreSingleSoundIfNeeded(soundsFullyLoaded: Bool = false) -> Bool {
    guard let savedSingleFileName = GlobalSettings.shared.getSavedSingleSoundFileName() else {
      return false
    }
    if singleSound?.fileName == savedSingleFileName { return true }
    if let singleSound = sounds.first(where: { $0.fileName == savedSingleFileName }) {
      Logger.audio.debug("AudioManager: Restoring single-sound mode for '\(singleSound.title)'")
      enterSingleSound(for: singleSound, startPlaying: GlobalSettings.shared.autoPlayOnLaunch)
      return true
    }
    if soundsFullyLoaded {
      // The sound was deleted, so launch falls back to the preset.
      Logger.audio.debug(
        "AudioManager: Saved single sound '\(savedSingleFileName)' is gone; clearing")
      GlobalSettings.shared.saveSingleSound(fileName: nil)
      return false
    }
    Logger.audio.debug(
      "AudioManager: Single sound '\(savedSingleFileName)' not loaded yet; deferring restore")
    return true
  }

  /// Launch state for a preset with no single sound: plays when `autoPlayOnLaunch` is set
  /// and sounds are selected, otherwise publishes a paused Now Playing.
  @MainActor
  func applyPresetLaunchState() {
    let preset = PresetManager.shared.currentPreset
    if GlobalSettings.shared.autoPlayOnLaunch, sounds.contains(where: { $0.isSelected }) {
      isGloballyPlaying = true
      launchAutoPlayHandled = true
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
  func enterSingleSound(for sound: Sound, startPlaying: Bool = true) {
    // Re-entering would save the single sound volume (1.0) as the original volume.
    if singleSound?.id == sound.id { return }

    Logger.audio.debug("AudioManager: Entering single-sound mode for '\(sound.title)'")

    exitPreviewMode(resuming: false)
    discardUnsavedMix()

    // Persist a pending (coalesced) mix edit before single sound stops preset saves.
    PresetManager.shared.updateCurrentPresetState()

    // Single sound and Quick Mix are exclusive. No resume, since a single sound pauses the mix.
    if isQuickMix {
      exitQuickMix(resuming: false)
    }

    // Spatial sessions are bound to the preset mix, so playing a single sound ends them.
    if SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }

    // Switching from another single sound: restore its volume and selection so it
    // doesn't join the mix at full volume.
    restoreSingleSoundState()

    singleSoundOriginalVolume = sound.volume
    singleSoundOriginalSelection = sound.isSelected

    // Pause the others but keep their selection, which belongs to the preset.
    for otherSound in sounds where otherSound.id != sound.id {
      otherSound.pause()
    }

    singleSound = sound
    GlobalSettings.shared.saveSingleSound(fileName: sound.fileName)
    updateNextPreviousCommandState()
    sound.volume = 1.0
    sound.isSelected = true

    // Loading applies a random start position. A reused stopped player needs it reset.
    if !sound.isLoaded {
      sound.loadSound()
    } else if !sound.isPlaying {
      sound.resetSoundPosition()
    }

    // When restoring paused (launch with auto-play off), the selected sound
    // resumes from the play/pause control.
    if startPlaying {
      setGlobalPlaybackState(true)
      sound.play()
    } else {
      isGloballyPlaying = false
    }

    nowPlayingManager.updateInfo(
      presetName: sound.title,
      isPlaying: startPlaying
    )
  }

  /// Pauses the single sound and restores the volume and selection it had before.
  /// Leaves global playback and `singleSound` to the caller.
  @MainActor
  private func restoreSingleSoundState() {
    guard let singleSound = singleSound else { return }

    singleSound.pause()

    if let originalVolume = singleSoundOriginalVolume {
      singleSound.volume = originalVolume
      singleSoundOriginalVolume = nil
    }

    if let originalSelection = singleSoundOriginalSelection {
      singleSound.isSelected = originalSelection
      singleSoundOriginalSelection = nil
    }
  }

  @MainActor
  func exitSingleSound() {
    guard singleSound != nil else { return }
    Logger.audio.debug("AudioManager: Exiting single-sound mode")

    restoreSingleSoundState()
    singleSound = nil
    GlobalSettings.shared.saveSingleSound(fileName: nil)
    setGlobalPlaybackState(false)

    // A single sound restored at launch skips applySoundStates, so presetStatesApplied is
    // still false. Playback is stopped first so this re-sync can't autoplay.
    if !PresetManager.shared.presetStatesApplied,
      let preset = PresetManager.shared.currentPreset
    {
      PresetManager.shared.applySoundStates(preset.soundStates)
    }

    updateNextPreviousCommandState()
    nowPlayingManager.updateInfo(
      presetName: "Blankie",
      isPlaying: false
    )

    Logger.audio.debug("AudioManager: Exit single-sound mode complete")
  }

  @MainActor
  func exitSingleSoundWithoutResuming() {
    guard singleSound != nil else { return }
    Logger.audio.debug("AudioManager: Exiting single-sound mode (without resuming)")

    restoreSingleSoundState()
    singleSound = nil
    GlobalSettings.shared.saveSingleSound(fileName: nil)

    // Same re-sync as exitSingleSound. Skipped when applySoundStates is the caller,
    // so its isApplyingPresetStates window stays open.
    if !isApplyingPresetStates, !PresetManager.shared.presetStatesApplied,
      let preset = PresetManager.shared.currentPreset
    {
      PresetManager.shared.applySoundStates(preset.soundStates)
    }

    updateNextPreviousCommandState()

    Logger.audio.debug("AudioManager: Exit single-sound mode (without resuming) complete")
  }
}
