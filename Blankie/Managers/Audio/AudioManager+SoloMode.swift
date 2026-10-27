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
  /// solo token or its sound no longer exists.
  func sound(forSoloToken token: String) -> Sound? {
    guard let fileName = GlobalSettings.soloFileName(fromToken: token) else { return nil }
    return sounds.first { $0.fileName == fileName }
  }

  @MainActor
  func toggleSoloMode(for sound: Sound) {
    if soloModeSound?.id == sound.id {
      exitSoloMode()
    } else {
      enterSoloMode(for: sound)
    }
  }

  /// Restores a saved solo sound, playing only when `autoPlayOnLaunch` is set.
  /// Returns true if the solo was restored or its custom sound hasn't loaded yet
  /// (launch skips the preset). Once `soundsFullyLoaded`, a missing sound clears
  /// the saved solo and returns false.
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
      // The sound was deleted; launch falls back to the preset.
      Logger.audio.debug("AudioManager: Saved solo sound '\(savedSoloFileName)' is gone; clearing")
      GlobalSettings.shared.saveSoloModeSound(fileName: nil)
      return false
    }
    Logger.audio.debug(
      "AudioManager: Solo sound '\(savedSoloFileName)' not loaded yet; deferring restore")
    return true
  }

  /// Launch state for a preset with no solo: plays when `autoPlayOnLaunch` is set
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
  func enterSoloMode(for sound: Sound, startPlaying: Bool = true) {
    // Re-entering would save the solo volume (1.0) as the original volume.
    if soloModeSound?.id == sound.id { return }

    Logger.audio.debug("AudioManager: Entering solo mode for '\(sound.title)'")

    exitPreviewMode(resuming: false)

    // Persist a pending (coalesced) mix edit before solo stops preset saves.
    PresetManager.shared.updateCurrentPresetState()

    // Solo and Quick Mix are mutually exclusive. No resume, since solo pauses the mix.
    if isQuickMix {
      exitQuickMix(resuming: false)
    }

    // Spatial sessions are bound to the preset mix; soloing ends them.
    if SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }

    // Switching from another solo sound: restore its volume and selection so it
    // doesn't join the mix at full volume.
    restoreSoloSoundState()

    soloModeOriginalVolume = sound.volume
    soloModeOriginalSelection = sound.isSelected

    // Pause the others but keep their selection, which belongs to the preset.
    for otherSound in sounds where otherSound.id != sound.id {
      otherSound.pause()
    }

    soloModeSound = sound
    GlobalSettings.shared.saveSoloModeSound(fileName: sound.fileName)
    updateNextPreviousCommandState()
    sound.volume = 1.0
    sound.isSelected = true

    // Loading applies a random start position; a reused stopped player needs it reset.
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

  /// Pauses the soloed sound and restores its pre-solo volume and selection.
  /// Leaves global playback and `soloModeSound` to the caller.
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
    soloModeSound = nil
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)
    setGlobalPlaybackState(false)

    // A solo restored at launch skips applySoundStates, so presetStatesApplied is
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

    Logger.audio.debug("AudioManager: Exit solo mode complete")
  }

  @MainActor
  func exitSoloModeWithoutResuming() {
    guard soloModeSound != nil else { return }
    Logger.audio.debug("AudioManager: Exiting solo mode (without resuming)")

    restoreSoloSoundState()
    soloModeSound = nil
    GlobalSettings.shared.saveSoloModeSound(fileName: nil)

    // Same re-sync as exitSoloMode. Skipped when applySoundStates is the caller,
    // so its isApplyingPresetStates window stays open.
    if !isApplyingPresetStates, !PresetManager.shared.presetStatesApplied,
      let preset = PresetManager.shared.currentPreset
    {
      PresetManager.shared.applySoundStates(preset.soundStates)
    }

    updateNextPreviousCommandState()

    Logger.audio.debug("AudioManager: Exit solo mode (without resuming) complete")
  }

  // MARK: - Preview Mode (for SoundSheet previews)

  @MainActor
  func enterPreviewMode(for sound: Sound) {
    Logger.audio.debug("AudioManager: Entering preview mode for '\(sound.title)'")

    // Persist a pending (coalesced) mix edit before preview stops preset saves.
    PresetManager.shared.updateCurrentPresetState()

    previewModeOriginalStates.removeAll()
    for existingSound in sounds {
      previewModeOriginalStates[existingSound.fileName] = PreviewOriginalState(
        volume: existingSound.volume,
        isPlaying: existingSound.isPlaying
      )
    }

    for otherSound in sounds where otherSound.id != sound.id {
      if otherSound.isPlaying {
        otherSound.pause()
      }
    }

    previewModeSound = sound

    #if os(iOS) || os(visionOS)
      // Previews play while globally paused, when playSelected() (which normally
      // activates the session) never runs.
      setupAudioSessionForPlayback()
    #endif

    sound.volume = 1.0

    if !sound.isLoaded {
      sound.loadSound()
    }

    // Applies any temporary customizations on top of full volume.
    sound.updateVolume()

    let wasAlreadyPlaying = previewModeOriginalStates[sound.fileName]?.isPlaying ?? false
    if !wasAlreadyPlaying {
      sound.resetSoundPosition()
    }
    sound.play()

    Logger.audio.debug("AudioManager: Preview mode started for '\(sound.title)'")
  }

  /// `resuming: false` restores volumes without restarting the pre-preview
  /// mix, for callers that start or replace playback right after.
  @MainActor
  func exitPreviewMode(resuming: Bool = true, pauseFadeDuration: TimeInterval? = nil) {
    guard let previewSound = previewModeSound else { return }
    Logger.audio.debug("AudioManager: Exiting preview mode for '\(previewSound.title)'")

    let previewSoundWasPlaying =
      previewModeOriginalStates[previewSound.fileName]?.isPlaying ?? false
    if !previewSoundWasPlaying {
      previewSound.pause(fadeDuration: pauseFadeDuration)
    }

    for sound in sounds {
      if let originalState = previewModeOriginalStates[sound.fileName] {
        sound.volume = originalState.volume
        sound.updateVolume()

        // isSelected can flip mid-preview, so a deselected sound stays off. No
        // isPlaying guard: play() rescues a sound mid fade-out, since
        // node.isPlaying lags playbackState by about 0.5s.
        if resuming, originalState.isPlaying, isGloballyPlaying, sound.isSelected {
          sound.play()
        }
      }
    }

    previewModeSound = nil
    previewModeOriginalStates.removeAll()

    // A mix emptied during the preview pauses now.
    updateHasSelectedSounds()

    // A preview while paused ran the engine; idle it after the fade so iOS
    // stops reporting the app as playing.
    if !isGloballyPlaying {
      scheduleEngineIdlePause(afterFade: Sound.fadeDuration)
    }

    Logger.audio.debug("AudioManager: Preview mode exited")
  }
}
