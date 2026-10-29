//
//  AudioManager+UnsavedMix.swift
//  Blankie
//
//  Created by Cody Bromley on 10/29/26.
//
//  A single sound grows into an unsaved mix when another sound is added. Like Quick Mix,
//  it clears the current preset while it lasts, so nothing it does is saved into one.
//

import Foundation
import os

extension AudioManager {
  /// The mix's sounds in the order they were added, including any switched off.
  @MainActor
  var unsavedMixSounds: [Sound] {
    guard let unsavedMix else { return [] }
    return unsavedMix.soundFileNames.compactMap { name in
      sounds.first { $0.fileName == name }
    }
  }

  /// The + button: a single sound becomes a mix, and a mix grows. Saved presets add
  /// sounds in their editor, so nothing happens there.
  @MainActor
  func addSound(_ sound: Sound) {
    if singleSound != nil {
      startUnsavedMix(adding: sound)
    } else if unsavedMix != nil {
      addToUnsavedMix(sound)
    }
  }

  /// Whether the + button applies: a single sound or an unsaved mix.
  @MainActor
  var canAddSound: Bool {
    singleSound != nil || unsavedMix != nil
  }

  /// The sounds the + checklist shows checked.
  @MainActor
  var soundsInCurrentMix: Set<String> {
    if let singleSound { return [singleSound.fileName] }
    return Set(unsavedMix?.soundFileNames ?? [])
  }

  /// The checklist's edit: adds the newly checked sounds and removes the unchecked ones.
  @MainActor
  func setMixSounds(_ fileNames: Set<String>) {
    let current = soundsInCurrentMix
    for sound in sounds where fileNames.contains(sound.fileName) {
      if !current.contains(sound.fileName) { addSound(sound) }
    }
    for sound in sounds where current.contains(sound.fileName) {
      if !fileNames.contains(sound.fileName) { removeFromUnsavedMix(sound) }
    }
  }

  /// Turns the playing single sound into a mix with `sound`. The single sound keeps its
  /// volume, and its saved key stays so a relaunch comes back to it.
  @MainActor
  func startUnsavedMix(adding sound: Sound) {
    guard unsavedMix == nil, let origin = singleSound, origin.id != sound.id else { return }
    Logger.audio.debug("AudioManager: Starting an unsaved mix from '\(origin.fileName)'")

    // What each sound had before single sound, so a discard puts the preset's mix back.
    unsavedMixOriginalStates = sounds.map { item in
      guard item.id == origin.id else {
        return QuickMixState(sound: item, isSelected: item.isSelected, volume: item.volume)
      }
      return QuickMixState(
        sound: item, isSelected: singleSoundOriginalSelection ?? item.isSelected,
        volume: singleSoundOriginalVolume ?? item.volume)
    }
    singleSoundOriginalVolume = nil
    singleSoundOriginalSelection = nil

    preUnsavedMixPreset = PresetManager.shared.currentPreset
    PresetManager.shared.clearCurrentPreset()

    let name = UnsavedMix.generatedName(
      first: origin.localizedTitle, second: sound.localizedTitle)
    unsavedMix = UnsavedMix(
      name: name, originSoundFileName: origin.fileName, soundFileNames: [origin.fileName])

    // The preset's other sounds were already silent in single sound.
    for other in sounds where other.id != origin.id {
      other.isSelected = false
    }
    singleSound = nil
    updateNextPreviousCommandState()

    addToUnsavedMix(sound)
  }

  /// Adds a sound to the mix.
  @MainActor
  func addToUnsavedMix(_ sound: Sound) {
    guard var unsavedMix else { return }
    // A mix holds one music sound, so new music replaces the old (see `Sound.isSelected`).
    if sound.isMusic {
      let music = Set(sounds.filter(\.isMusic).map(\.fileName))
      unsavedMix.soundFileNames.removeAll { music.contains($0) && $0 != sound.fileName }
    }
    if !unsavedMix.soundFileNames.contains(sound.fileName) {
      unsavedMix.soundFileNames.append(sound.fileName)
    }
    self.unsavedMix = unsavedMix
    sound.isSelected = true
    setGlobalPlaybackState(true)
    sound.play()
    // Music replacing the only other sound can leave just one.
    if !collapseUnsavedMixIfOneSound() {
      refreshUnsavedMixName()
      nowPlayingManager.updateInfo(presetName: self.unsavedMix?.name, isPlaying: true)
    }
  }

  /// Renames the mix after its sounds that are on, and republishes Now Playing on a change.
  @MainActor
  func refreshUnsavedMixName() {
    guard var unsavedMix,
      let name = UnsavedMix.name(
        forTitles: unsavedMixSounds.filter(\.isSelected).map(\.localizedTitle)),
      name != unsavedMix.name
    else { return }
    unsavedMix.name = name
    self.unsavedMix = unsavedMix
    nowPlayingManager.updateInfo(presetName: name, isPlaying: isGloballyPlaying)
  }

  /// Puts the mix's sounds in the order a drag in the mixer leaves them.
  @MainActor
  func reorderUnsavedMix(_ fileNames: [String]) {
    guard var unsavedMix else { return }
    let members = Set(unsavedMix.soundFileNames)
    let moved = fileNames.filter(members.contains)
    unsavedMix.soundFileNames = moved + unsavedMix.soundFileNames.filter { !moved.contains($0) }
    self.unsavedMix = unsavedMix
    refreshUnsavedMixName()
  }

  /// After a sound is switched on or off: with one left on it plays on its own, and
  /// otherwise the name follows. Runs from the coalesced sound refresh.
  @MainActor
  func reconcileUnsavedMix() {
    if !collapseUnsavedMixIfOneSound() {
      refreshUnsavedMixName()
    }
  }

  /// Takes a sound out of the mix and switches it off. The last sound stays.
  @MainActor
  func removeFromUnsavedMix(_ sound: Sound) {
    guard var unsavedMix, unsavedMix.soundFileNames.count > 1,
      let index = unsavedMix.soundFileNames.firstIndex(of: sound.fileName)
    else { return }
    unsavedMix.soundFileNames.remove(at: index)
    self.unsavedMix = unsavedMix
    sound.isSelected = false
    reconcileUnsavedMix()
  }

  /// With one sound left on, the mix turns back into that sound on its own, which keeps
  /// playing. Returns whether it did.
  @MainActor
  @discardableResult
  func collapseUnsavedMixIfOneSound() -> Bool {
    let playing = unsavedMixSounds.filter(\.isSelected)
    guard unsavedMix != nil, playing.count == 1, let remaining = playing.first else {
      return false
    }
    Logger.audio.debug("AudioManager: Unsaved mix is down to '\(remaining.fileName)'")

    // Single sound comes first so the preset's sounds restored below stay silent.
    singleSound = remaining
    let originals = unsavedMixOriginalStates
    for state in originals where state.sound.id != remaining.id {
      state.sound.volume = state.volume
      state.sound.isSelected = state.isSelected
    }
    let original = originals.first { $0.sound.id == remaining.id }
    singleSoundOriginalVolume = original?.volume ?? remaining.volume
    singleSoundOriginalSelection = original?.isSelected ?? false
    // Restoring the preset's music can deselect a music sound left on its own.
    remaining.isSelected = true
    remaining.volume = 1.0

    unsavedMix = nil
    unsavedMixOriginalStates = []
    pendingLeave = nil
    let (preset, changed) = takeStashedPreset()
    PresetManager.shared.setCurrentPreset(preset)
    // Leaving the single sound re-applies a preset that changed during the mix.
    if changed { PresetManager.shared.presetStatesApplied = false }
    GlobalSettings.shared.saveSingleSound(fileName: remaining.fileName)
    updateNextPreviousCommandState()
    nowPlayingManager.updateInfo(presetName: remaining.title, isPlaying: isGloballyPlaying)
    return true
  }

  /// Runs `action` now, or with an unsaved mix, holds it until the save prompt is answered.
  /// For in-app controls only. Siri, widgets and other outside paths discard instead.
  @MainActor
  func leaveUnsavedMixAsking(then action: @escaping @MainActor () -> Void) {
    guard unsavedMix != nil else {
      action()
      return
    }
    pendingLeave = action
  }

  /// Lets the mix go and puts the earlier preset and its mix back without playing them.
  /// Does nothing without a mix.
  @MainActor
  func discardUnsavedMix() {
    guard unsavedMix != nil else { return }
    Logger.audio.debug("AudioManager: Discarding the unsaved mix")

    for sound in sounds {
      sound.pause()
    }
    for state in unsavedMixOriginalStates {
      state.sound.volume = state.volume
      state.sound.isSelected = state.isSelected
    }
    unsavedMixOriginalStates = []
    unsavedMix = nil
    pendingLeave = nil
    // The mix kept its single sound's key for a relaunch. Letting it go ends that too.
    GlobalSettings.shared.saveSingleSound(fileName: nil)

    let presetManager = PresetManager.shared
    let (preset, changed) = takeStashedPreset()
    presetManager.setCurrentPreset(preset)
    // A launch into single sound skipped the preset's apply (as exitSingleSound re-syncs),
    // and one edited or deleted during the mix no longer matches the restored sounds.
    if let preset, changed || !presetManager.presetStatesApplied {
      presetManager.applySoundStates(preset.soundStates)
    }
    updateNextPreviousCommandState()
  }

  /// Clears the preset from before the mix and returns it as saved now, so an edit during
  /// the mix sticks. One deleted during the mix falls back to All Blankie Sounds.
  /// `changed` is whether it differs from the copy taken when the mix started.
  @MainActor
  private func takeStashedPreset() -> (preset: Preset?, changed: Bool) {
    guard let stash = preUnsavedMixPreset else { return (nil, false) }
    preUnsavedMixPreset = nil
    let presets = PresetManager.shared.presets
    let preset = presets.first { $0.id == stash.id } ?? presets.first(where: \.isDefault)
    return (preset, preset != stash)
  }

  /// Makes `preset`, just saved from the mix, the current preset. The mix keeps playing
  /// without a restart, and launch now opens to the preset.
  @MainActor
  func adoptUnsavedMix(as preset: Preset) {
    guard unsavedMix != nil else { return }
    Logger.audio.debug("AudioManager: Saved the unsaved mix as '\(preset.name)'")

    unsavedMix = nil
    unsavedMixOriginalStates = []
    preUnsavedMixPreset = nil
    pendingLeave = nil
    GlobalSettings.shared.saveSingleSound(fileName: nil)

    let presetManager = PresetManager.shared
    presetManager.setCurrentPreset(preset)
    PresetStorage.saveLastActivePresetID(preset.id)
    // The sheet may have changed the sounds, so match them. Ones already playing carry on.
    presetManager.applySoundStates(preset.soundStates)
    updateNextPreviousCommandState()
  }
}
