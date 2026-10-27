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

  /// Exits single sound, then Quick Mix, before a preset switch. The pre-Quick-Mix mix
  /// is dropped unless `restoringQuickMix` is set, since the preset replaces it.
  @MainActor
  func leaveTransientModes(restoringQuickMix: Bool = false) {
    exitSingleSoundWithoutResuming()
    exitQuickMix(restoring: restoringQuickMix)
  }

  @MainActor
  func enterQuickMix(with initialSounds: [Sound] = []) {
    Logger.audio.debug("AudioManager: Entering Quick Mix mode")

    exitPreviewMode(resuming: false)

    // Persist a pending (coalesced) mix edit before Quick Mix clears the preset.
    PresetManager.shared.updateCurrentPresetState()

    if singleSound != nil {
      exitSingleSoundWithoutResuming()
    }

    preQuickMixPreset = PresetManager.shared.currentPreset
    PresetManager.shared.clearCurrentPreset()

    // Spatial sessions are bound to the preset mix, so Quick Mix ends them.
    if SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }

    quickMixOriginalStates = sounds.map { sound in
      QuickMixState(sound: sound, isSelected: sound.isSelected, volume: sound.volume)
    }

    // Fading everything out first makes entering Quick Mix a crossfade.
    for sound in sounds {
      sound.pause()
      sound.isSelected = false
    }

    isQuickMix = true
    updateNextPreviousCommandState()

    let quickMixSounds = GlobalSettings.shared.quickMixSoundFileNames
    let validInitialSounds = initialSounds.filter { sound in
      quickMixSounds.contains(sound.fileName)
    }

    Logger.audio.debug(
      "AudioManager: Filtered \(initialSounds.count) initial sounds to \(validInitialSounds.count) valid Quick Mix sounds"
    )

    for sound in sounds where quickMixSounds.contains(sound.fileName) {
      sound.volume = 0.8
      Logger.audio.debug("AudioManager: Reset \(sound.fileName) volume to 80%")
    }

    for sound in validInitialSounds {
      sound.isSelected = true
      sound.play()
    }

    let hasActiveSounds = sounds.contains { $0.isSelected && $0.isPlaying }
    setGlobalPlaybackState(hasActiveSounds)

    nowPlayingManager.updateInfo(
      presetName: "Quick Mix",
      isPlaying: hasActiveSounds
    )
  }

  /// `restoring: false` drops the pre-Quick-Mix mix and preset (a preset apply
  /// follows). `resuming: false` restores them without starting playback.
  @MainActor
  func exitQuickMix(restoring: Bool = true, resuming: Bool = true) {
    guard isQuickMix else { return }
    Logger.audio.debug("AudioManager: Exiting Quick Mix mode")

    for sound in sounds {
      sound.pause()
    }

    for state in quickMixOriginalStates {
      state.sound.volume = state.volume
      guard restoring else {
        state.sound.isSelected = false
        continue
      }
      state.sound.isSelected = state.isSelected

      if state.isSelected, isGloballyPlaying, resuming {
        state.sound.play()
      }
    }

    quickMixOriginalStates = []
    isQuickMix = false
    updateNextPreviousCommandState()

    if restoring, let savedPreset = preQuickMixPreset {
      Logger.audio.debug("AudioManager: Restoring previous preset: '\(savedPreset.name)'")
      PresetManager.shared.setCurrentPreset(savedPreset)

      nowPlayingManager.updateInfo(
        preset: savedPreset,
        presetName: savedPreset.name,
        creatorName: savedPreset.creatorName,
        artworkId: savedPreset.artworkId,
        isPlaying: isGloballyPlaying
      )
    } else {
      nowPlayingManager.updateInfo(
        presetName: nil,
        creatorName: nil,
        isPlaying: isGloballyPlaying
      )
    }

    preQuickMixPreset = nil
  }

  /// After the Quick Mix editor's Done, stops and deselects any sound no longer
  /// in the mix. No-op outside an active Quick Mix session.
  @MainActor
  func reconcileQuickMixMembership() {
    guard isQuickMix else { return }
    let members = Set(GlobalSettings.shared.quickMixSoundFileNames)
    for sound in sounds where sound.isSelected && !members.contains(sound.fileName) {
      Logger.audio.debug("AudioManager: Quick Mix dropped '\(sound.fileName)' — stopping it")
      sound.isSelected = false
      sound.pause()
    }

    // The mix may now be empty.
    let hasActiveSounds = sounds.contains { $0.isSelected && $0.isPlaying }
    setGlobalPlaybackState(hasActiveSounds)

    nowPlayingManager.updateInfo(presetName: "Quick Mix", isPlaying: hasActiveSounds)
  }

  /// Widget volume buttons operate only on the current Quick Mix, so stale
  /// controls cannot alter a saved preset or start playback in another mode.
  @MainActor
  func adjustQuickMixSoundVolume(fileName: String, deltaPercent: Int) {
    guard isQuickMix,
      GlobalSettings.shared.quickMixSoundFileNames.contains(fileName),
      let target = sound(fileName: fileName)
    else { return }
    let current = Int((target.volume * 100).rounded())
    let step = min(5, max(-5, deltaPercent))
    target.volume = Float(min(100, max(0, current + step))) / 100
    publishCurrentWidgetSnapshot()
  }

  @MainActor
  func toggleQuickMixSound(_ sound: Sound) {
    guard isQuickMix else { return }

    if sound.isSelected {
      sound.isSelected = false
      sound.pause()
    } else {
      sound.isSelected = true
      sound.play()
    }

    let hasActiveSounds = sounds.contains { $0.isSelected && $0.isPlaying }
    setGlobalPlaybackState(hasActiveSounds)

    nowPlayingManager.updateInfo(
      presetName: "Quick Mix",
      isPlaying: hasActiveSounds
    )
  }
}
