//
//  UnsavedMixTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/29/26.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct UnsavedMixModelTests {

  @Test func nameJoinsTheFirstTwoTitles() {
    #expect(UnsavedMix.generatedName(first: "Rain", second: "Waves") == "Rain + Waves Mix")
  }
}

@Suite(.serialized) @MainActor final class UnsavedMixTests {
  private let sandbox: SingletonSandbox
  private let originalStarredItems: [String]
  private let originalQuickMixSounds: [String]
  private var audioManager: AudioManager { sandbox.audioManager }
  private var presetManager: PresetManager { sandbox.presetManager }

  init() async {
    sandbox = await SingletonSandbox.make(soundNames: [
      "test-mix-rain", "test-mix-waves", "test-mix-fan", "test-mix-lofi", "test-mix-guitar",
    ])
    originalStarredItems = GlobalSettings.shared.starredItems
    originalQuickMixSounds = GlobalSettings.shared.quickMixSoundFileNames
  }

  isolated deinit {
    sandbox.restore()
    GlobalSettings.shared.setStarredItems(originalStarredItems)
    GlobalSettings.shared.setQuickMixSoundFileNames(originalQuickMixSounds)
  }

  // MARK: - Helpers

  private struct Sounds {
    let rain: TestSound
    let waves: TestSound
    let fan: TestSound
    let lofi: TestSound
    let guitar: TestSound
  }

  private func makeSounds() -> Sounds {
    let sounds = Sounds(
      rain: TestSound(fileName: "test-mix-rain"),
      waves: TestSound(fileName: "test-mix-waves"),
      fan: TestSound(fileName: "test-mix-fan"),
      lofi: TestSound(fileName: "test-mix-lofi", isMusic: true),
      guitar: TestSound(fileName: "test-mix-guitar", isMusic: true))
    let all = [sounds.rain, sounds.waves, sounds.fan, sounds.lofi, sounds.guitar]
    for sound in all { sound.volume = 0.5 }
    audioManager.sounds = all
    audioManager.defaultSoundOrder = all.map(\.fileName)
    return sounds
  }

  /// A custom preset holding `fan` (selected) and `waves`, installed as current and applied.
  private func installPreset(_ sounds: Sounds) async -> Preset {
    sounds.fan.isSelected = true
    let preset = PresetFactory.makePreset(
      name: "Mix Test Preset",
      soundStates: [
        PresetState(fileName: sounds.fan.fileName, isSelected: true, volume: 0.5),
        PresetState(fileName: sounds.waves.fileName, isSelected: false, volume: 0.5),
      ],
      soundOrder: [sounds.fan.fileName, sounds.waves.fileName])
    presetManager.setPresets([preset])
    presetManager.setCurrentPreset(preset)
    presetManager.presetStatesApplied = true
    await sandbox.settle()
    return preset
  }

  /// Plays `rain` on its own, then adds `waves`.
  private func startMix(_ sounds: Sounds) {
    audioManager.enterSingleSound(for: sounds.rain)
    audioManager.startUnsavedMix(adding: sounds.waves)
  }

  private var expectedName: String {
    UnsavedMix.generatedName(first: "test-mix-rain", second: "test-mix-waves")
  }

  private func stop() {
    audioManager.discardUnsavedMix()
    audioManager.exitSingleSoundWithoutResuming()
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Starting and growing

  @Test func startFromSingleSoundMakesNamedMix() async {
    let sounds = makeSounds()
    _ = await installPreset(sounds)

    startMix(sounds)

    #expect(audioManager.unsavedMix?.name == expectedName)
    #expect(audioManager.unsavedMix?.originSoundFileName == "test-mix-rain")
    #expect(audioManager.singleSound == nil)
    #expect(presetManager.currentPreset == nil)
    #expect(sounds.rain.isSelected)
    #expect(sounds.waves.isSelected)
    #expect(!sounds.fan.isSelected)
    #expect(audioManager.isGloballyPlaying)
    #expect(audioManager.unsavedMixSounds.map(\.fileName) == ["test-mix-rain", "test-mix-waves"])
    stop()
  }

  @Test func threeOrMoreSoundsAreACustomMix() async {
    let sounds = makeSounds()
    startMix(sounds)

    audioManager.addToUnsavedMix(sounds.fan)

    #expect(audioManager.unsavedMix?.name == String(localized: "Custom Mix"))
    #expect(audioManager.unsavedMixSounds.count == 3)
    stop()
  }

  /// Two sounds on name the mix in the order they were added.
  @Test func nameFollowsTheSoundsThatAreOn() async {
    let sounds = makeSounds()
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)

    audioManager.removeFromUnsavedMix(sounds.waves)
    #expect(
      audioManager.unsavedMix?.name
        == UnsavedMix.generatedName(first: "test-mix-rain", second: "test-mix-fan"))

    audioManager.addToUnsavedMix(sounds.waves)
    audioManager.toggleOrResume(sounds.rain)
    await sandbox.waitUntil {
      self.audioManager.unsavedMix?.name != String(localized: "Custom Mix")
    }
    #expect(
      audioManager.unsavedMix?.name
        == UnsavedMix.generatedName(first: "test-mix-fan", second: "test-mix-waves"))
    stop()
  }

  @Test func addingSecondMusicSoundKeepsOne() async {
    let sounds = makeSounds()
    audioManager.enterSingleSound(for: sounds.rain)
    audioManager.startUnsavedMix(adding: sounds.lofi)

    audioManager.addToUnsavedMix(sounds.guitar)

    // The music it replaced leaves the mix, so the checklist doesn't show it checked.
    #expect(audioManager.unsavedMixSounds.map(\.fileName) == ["test-mix-rain", "test-mix-guitar"])
    #expect(!sounds.lofi.isSelected)
    stop()
  }

  @Test func mixerListsOnlyTheMixSounds() async {
    let sounds = makeSounds()
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)
    // Switched off in the mixer, a sound stays in the mix.
    sounds.waves.isSelected = false

    let listed = audioManager.orderedVisibleSounds(for: presetManager.currentPreset)
    #expect(listed.map(\.fileName) == ["test-mix-rain", "test-mix-waves", "test-mix-fan"])
    stop()
  }

  @Test func aPausedTapRenamesTheMix() async {
    let sounds = makeSounds()
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)
    audioManager.toggleOrResume(sounds.fan)
    await sandbox.waitUntil { self.audioManager.unsavedMix?.name == self.expectedName }
    audioManager.setGlobalPlaybackState(false)

    // Paused, a tap switches the sound on and resumes.
    audioManager.toggleOrResume(sounds.fan)
    await sandbox.waitUntil {
      self.audioManager.unsavedMix?.name == String(localized: "Custom Mix")
    }
    #expect(audioManager.unsavedMix?.name == String(localized: "Custom Mix"))
    stop()
  }

  @Test func reorderingTheMixLeavesAllSoundsAlone() async {
    let sounds = makeSounds()
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)
    let allSoundsOrder = audioManager.defaultSoundOrder

    audioManager.reorderUnsavedMix(["test-mix-fan", "test-mix-rain", "test-mix-waves"])

    #expect(
      audioManager.orderedVisibleSounds(for: nil).map(\.fileName)
        == ["test-mix-fan", "test-mix-rain", "test-mix-waves"])
    #expect(audioManager.defaultSoundOrder == allSoundsOrder)
    stop()
  }

  @Test func aSecondCustomMixGetsANumber() async {
    let existing = PresetFactory.makePreset(name: "custom mix ")
    presetManager.setPresets([existing])

    #expect(presetManager.uniquePresetName("Custom Mix") == "Custom Mix (2)")
    #expect(presetManager.uniquePresetName("Rain + Waves Mix") == "Rain + Waves Mix")
  }

  // MARK: - Never written into a preset

  @Test func savingWhileMixedLeavesPresetsUntouched() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    // As stored, since saving puts the states in the default sound order.
    let storedStates = presetManager.presets.first { $0.id == preset.id }?.soundStates
    startMix(sounds)

    sounds.waves.volume = 0.9
    presetManager.updateCurrentPresetState()
    presetManager.savePresets()
    await sandbox.settle()

    #expect(presetManager.presets.first { $0.id == preset.id }?.soundStates == storedStates)
    stop()
  }

  // MARK: - Leaving

  @Test func discardRestoresThePresetWithoutPlaying() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)
    sounds.waves.volume = 0.9

    audioManager.discardUnsavedMix()

    #expect(audioManager.unsavedMix == nil)
    #expect(presetManager.currentPreset?.id == preset.id)
    #expect(sounds.fan.isSelected)
    #expect(!sounds.rain.isSelected)
    #expect(!sounds.waves.isSelected)
    #expect(sounds.waves.volume == 0.5)
    #expect(sounds.rain.volume == 0.5)
    stop()
  }

  /// Once let go, the mix's single sound is no longer what a relaunch comes back to.
  @Test func discardAfterThePresetIsDeletedRestoresAllSounds() async {
    let sounds = makeSounds()
    _ = await installPreset(sounds)
    let defaultPreset = PresetFactory.makePreset(name: "Default", isDefault: true)
    startMix(sounds)
    presetManager.setPresets([defaultPreset])

    audioManager.discardUnsavedMix()

    #expect(presetManager.currentPreset?.id == defaultPreset.id)
    stop()
  }

  @Test func discardBringsBackTheEditedPreset() async {
    let sounds = makeSounds()
    var preset = await installPreset(sounds)
    startMix(sounds)
    preset.name = "Renamed During Mix"
    presetManager.setPresets([preset])

    audioManager.discardUnsavedMix()

    #expect(presetManager.currentPreset?.name == "Renamed During Mix")
    stop()
  }

  @Test func nextFromAMixCountsFromItsSound() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    GlobalSettings.shared.setStarredItems([
      "solo:test-mix-rain", preset.id.uuidString, "solo:test-mix-fan",
    ])
    startMix(sounds)

    audioManager.navigateToNextPreset()

    #expect(audioManager.singleSound == nil)
    #expect(presetManager.currentPreset?.id == preset.id)
    stop()
  }

  @Test func discardForgetsTheOriginSingleSound() async {
    let sounds = makeSounds()
    _ = await installPreset(sounds)
    startMix(sounds)

    audioManager.discardUnsavedMix()

    #expect(GlobalSettings.shared.getSavedSingleSoundFileName() == nil)
    stop()
  }

  @Test func intentsDiscardTheMix() async throws {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    GlobalSettings.shared.setQuickMixSoundFileNames([sounds.fan.fileName])
    GlobalSettings.shared.setStarredItems([preset.id.uuidString, "solo:test-mix-fan"])

    // Siri or Shortcuts playing a sound.
    startMix(sounds)
    var playSound = PlaySoundIntent()
    playSound.sound = SoundEntity(sound: sounds.fan)
    _ = try await playSound.perform()
    #expect(audioManager.unsavedMix == nil)
    stop()

    // A Quick Mix widget tap.
    startMix(sounds)
    _ = try await WidgetToggleQuickMixSoundIntent(fileName: sounds.fan.fileName).perform()
    #expect(audioManager.unsavedMix == nil)
    audioManager.exitQuickMix(resuming: false)
    stop()

    // Siri, a widget or CarPlay playing a preset.
    startMix(sounds)
    var playPreset = PlayPresetIntent()
    playPreset.preset = PresetEntity(preset: preset)
    _ = try await playPreset.perform()
    #expect(audioManager.unsavedMix == nil)
    stop()

    // Remote next and previous.
    startMix(sounds)
    audioManager.navigateToNextPreset()
    #expect(audioManager.unsavedMix == nil)
    stop()
    startMix(sounds)
    audioManager.navigateToPreviousPreset()
    #expect(audioManager.unsavedMix == nil)
    stop()
  }

  /// Quitting keeps nothing of the mix. The next launch finds the single sound it grew from.
  @Test func relaunchRestoresOriginSingleSound() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)

    #expect(GlobalSettings.shared.getSavedSingleSoundFileName() == "test-mix-rain")

    // A new process starts with no in-memory mode and the preset unapplied.
    audioManager.unsavedMix = nil
    audioManager.preUnsavedMixPreset = nil
    audioManager.setGlobalPlaybackState(false)
    presetManager.setCurrentPreset(preset)
    presetManager.presetStatesApplied = false

    audioManager.restoreSingleSoundIfNeeded(soundsFullyLoaded: true)

    #expect(audioManager.singleSound?.fileName == "test-mix-rain")
    #expect(audioManager.unsavedMix == nil)
    stop()
  }

  // MARK: - Saving

  @Test func duplicateNameIgnoresCaseAndSpaces() async {
    presetManager.setPresets([PresetFactory.makePreset(name: "Rain + Waves Mix")])

    #expect(presetManager.hasPreset(named: " rain + waves mix"))
    #expect(presetManager.hasPreset(named: "Rain + Waves Mix"))
    #expect(!presetManager.hasPreset(named: "Rain + Fan Mix"))
  }

  @Test func savedMixBecomesTheCurrentPreset() async {
    let sounds = makeSounds()
    let original = await installPreset(sounds)
    startMix(sounds)
    sounds.waves.volume = 0.7
    let saved = PresetFactory.makePreset(
      name: expectedName,
      soundStates: audioManager.unsavedMixSounds.map {
        PresetState(fileName: $0.fileName, isSelected: true, volume: $0.volume)
      })
    presetManager.setPresets([original, saved])

    audioManager.adoptUnsavedMix(as: saved)

    #expect(audioManager.unsavedMix == nil)
    #expect(presetManager.currentPreset?.id == saved.id)
    #expect(presetManager.currentPreset?.name == expectedName)
    #expect(presetManager.presetStatesApplied)
    #expect(sounds.rain.isSelected && sounds.waves.isSelected)
    #expect(sounds.rain.volume == 1.0)
    #expect(sounds.waves.volume == 0.7)
    #expect(!sounds.fan.isSelected)
    #expect(GlobalSettings.shared.getSavedSingleSoundFileName() == nil)
    #expect(PresetStorage.loadLastActivePresetID() == saved.id)
    stop()
  }

  // MARK: - Asking first

  @Test func leavingAsksWhenMixed() async {
    let sounds = makeSounds()
    startMix(sounds)
    var ran = false

    audioManager.leaveUnsavedMixAsking { ran = true }

    #expect(!ran)
    #expect(audioManager.pendingLeave != nil)
    #expect(audioManager.unsavedMix != nil)
    audioManager.pendingLeave = nil
    stop()
  }

  @Test func leavingWithoutMixRunsNow() async {
    _ = makeSounds()
    var ran = false

    audioManager.leaveUnsavedMixAsking { ran = true }

    #expect(ran)
    #expect(audioManager.pendingLeave == nil)
  }

  // MARK: - Adding a sound

  @Test func addSoundRoutesByMode() async {
    let sounds = makeSounds()
    _ = await installPreset(sounds)

    // A saved preset adds sounds in its editor, so + doesn't apply.
    #expect(!audioManager.canAddSound)
    audioManager.addSound(sounds.rain)
    #expect(!sounds.rain.isSelected)
    #expect(audioManager.unsavedMix == nil)

    // A single sound starts a mix, and a mix grows.
    audioManager.enterSingleSound(for: sounds.guitar)
    #expect(audioManager.canAddSound)
    audioManager.addSound(sounds.waves)
    #expect(audioManager.unsavedMix != nil)
    audioManager.addSound(sounds.fan)
    #expect(audioManager.unsavedMixSounds.contains { $0.fileName == "test-mix-fan" })
    stop()
  }

  // MARK: - Removing a sound

  @Test func removingTakesTheSoundOutOfTheMix() async {
    let sounds = makeSounds()
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)

    audioManager.removeFromUnsavedMix(sounds.waves)

    #expect(audioManager.unsavedMixSounds.map(\.fileName) == ["test-mix-rain", "test-mix-fan"])
    #expect(!sounds.waves.isSelected)
    stop()
  }

  @Test func removingDownToOneSoundPlaysItOnItsOwn() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)

    audioManager.removeFromUnsavedMix(sounds.waves)

    #expect(audioManager.unsavedMix == nil)
    #expect(audioManager.singleSound?.fileName == "test-mix-rain")
    #expect(presetManager.currentPreset?.id == preset.id)
    #expect(GlobalSettings.shared.getSavedSingleSoundFileName() == "test-mix-rain")
    stop()
  }

  @Test func switchingOffDownToOneSoundPlaysItOnItsOwn() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)
    audioManager.addToUnsavedMix(sounds.fan)

    // Two of three still on stays a mix.
    audioManager.toggleOrResume(sounds.rain)
    await sandbox.settle()
    #expect(audioManager.unsavedMix != nil)

    audioManager.toggleOrResume(sounds.waves)
    await sandbox.waitUntil { self.audioManager.unsavedMix == nil }
    #expect(audioManager.unsavedMix == nil)
    #expect(audioManager.singleSound?.fileName == "test-mix-fan")
    #expect(presetManager.currentPreset?.id == preset.id)

    // Leaving the single sound puts the preset's mix back.
    audioManager.exitSingleSound()
    #expect(sounds.fan.isSelected)
    #expect(!sounds.rain.isSelected)
    stop()
  }

  // MARK: - The sound checklist

  @Test func checklistListsEveryAddableSound() async {
    let sounds = makeSounds()
    startMix(sounds)

    let candidates = MixSoundsPicker.candidates(from: audioManager.sounds)

    #expect(candidates.map(\.fileName).sorted() == audioManager.sounds.map(\.fileName).sorted())
    #expect(audioManager.soundsInCurrentMix == ["test-mix-rain", "test-mix-waves"])
    stop()
  }

  @Test func checklistAddsAndRemoves() async {
    let sounds = makeSounds()
    audioManager.enterSingleSound(for: sounds.rain)

    // Checking a second sound starts the mix.
    audioManager.setMixSounds(["test-mix-rain", "test-mix-waves"])
    #expect(audioManager.unsavedMix?.name == expectedName)

    audioManager.setMixSounds(["test-mix-rain", "test-mix-waves", "test-mix-fan"])
    audioManager.setMixSounds(["test-mix-rain", "test-mix-fan"])
    #expect(audioManager.unsavedMixSounds.map(\.fileName) == ["test-mix-rain", "test-mix-fan"])

    // Unchecking everything leaves one sound playing on its own.
    audioManager.setMixSounds([])
    #expect(audioManager.unsavedMix == nil)
    #expect(audioManager.singleSound != nil)
    stop()
  }

  // MARK: - Coming back

  /// Don't Save restores the preset paused, so tapping it in the Library has to re-apply it.
  @Test func returningToTheStashAfterDontSavePlaysIt() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)
    var applied: Bool?

    LibraryView.playPreset(preset, presentation: .sidebar) { applied = $0 }
    let action = audioManager.pendingLeave
    audioManager.discardUnsavedMix()
    action?()

    #expect(applied == true)
    await sandbox.waitForPresetApply()
    stop()
  }

  /// A launch into single sound skips the preset's apply, so a discard has to apply it.
  @Test func discardAfterLaunchIntoSingleRestoresThePreset() async {
    let sounds = makeSounds()
    _ = await installPreset(sounds)
    presetManager.presetStatesApplied = false
    sounds.fan.isSelected = false
    audioManager.enterSingleSound(for: sounds.rain, startPlaying: false)
    audioManager.startUnsavedMix(adding: sounds.waves)

    audioManager.discardUnsavedMix()

    #expect(sounds.fan.isSelected)
    #expect(!sounds.waves.isSelected)
    #expect(presetManager.presetStatesApplied)
    stop()
  }

  /// A mix let go from elsewhere takes its pending prompt with it.
  @Test func leavingTheMixClearsAPendingPrompt() async {
    let sounds = makeSounds()
    let preset = await installPreset(sounds)
    startMix(sounds)
    audioManager.leaveUnsavedMixAsking {}
    audioManager.discardUnsavedMix()
    #expect(audioManager.pendingLeave == nil)

    startMix(sounds)
    audioManager.leaveUnsavedMixAsking {}
    audioManager.adoptUnsavedMix(as: preset)
    #expect(audioManager.pendingLeave == nil)
    stop()
  }
}
