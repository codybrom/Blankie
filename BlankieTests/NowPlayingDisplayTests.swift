//
//  NowPlayingDisplayTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/26.
//
//  Backend-neutral display rules: lock screen title and artist, the widget's second line
//  and the scrubber anchor. Serialized: deinit restores every touched singleton value.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class NowPlayingDisplayTests {
  private let audioManager = AudioManager.shared
  private let originalAutoPlay: Bool
  private let originalSounds: [Sound]
  private let originalSingle: Sound?
  private let originalQuickMix: Bool
  private let originalUnsavedMix: UnsavedMix?
  private let originalDefaultSoundOrder: [String]
  private let originalPresets: [Preset]
  private let originalCurrentPreset: Preset?
  nonisolated private static let testNames = ["test-rain", "test-waves", "Rain"]

  init() {
    originalAutoPlay = GlobalSettings.shared.autoPlayOnLaunch
    originalSounds = audioManager.sounds
    originalSingle = audioManager.singleSound
    originalQuickMix = audioManager.isQuickMix
    originalUnsavedMix = audioManager.unsavedMix
    originalDefaultSoundOrder = audioManager.defaultSoundOrder
    originalPresets = PresetManager.shared.presets
    originalCurrentPreset = PresetManager.shared.currentPreset
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    AudioManager.shared.resetSounds()
    audioManager.singleSound = nil
    audioManager.isQuickMix = false
    audioManager.unsavedMix = nil
  }

  isolated deinit {
    audioManager.singleSound = originalSingle
    audioManager.isQuickMix = originalQuickMix
    audioManager.unsavedMix = originalUnsavedMix
    audioManager.defaultSoundOrder = originalDefaultSoundOrder
    audioManager.sounds = originalSounds
    PresetManager.shared.setPresets(originalPresets)
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
    GlobalSettings.shared.setAutoPlayOnLaunch(originalAutoPlay)
    for name in Self.testNames {
      UserDefaults.shared.removeObject(forKey: "\(name)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(name)_volume")
    }
  }

  /// Two selected TestSounds in a preset that fixes their order, so the title list is stable.
  private func selectTwoSoundsInOrder() {
    let rain = TestSound(fileName: "test-rain")
    let waves = TestSound(fileName: "test-waves")
    audioManager.sounds = [rain, waves]
    rain.isSelected = true
    waves.isSelected = true
    let preset = PresetFactory.makePreset(
      soundStates: Self.testNames.map {
        PresetState(fileName: $0, isSelected: true, volume: 0.5)
      },
      soundOrder: Self.testNames, creatorName: nil)
    PresetManager.shared.setCurrentPreset(preset)
  }

  // MARK: - Title

  /// The legacy name-only path uses the same title as the default preset tile.
  @Test func defaultPresetNameShowsAllBlankieSounds() {
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Default").title
        == String(localized: "All Blankie Sounds")
    )
  }

  /// The default preset uses its display name everywhere (Library, bar, mixer, Now Playing).
  @Test func defaultPresetActiveTitleIsItsDisplayName() {
    let builtIn = PresetFactory.makePreset(name: "Default", isDefault: true)
    #expect(builtIn.activeTitle == builtIn.displayName)
    let custom = PresetFactory.makePreset(name: "Rainy Night")
    #expect(custom.activeTitle == "Rainy Night")
  }

  /// A user's name that matches a legacy placeholder still shows verbatim.
  @Test func presetIdentityDeterminesTitle() {
    let builtIn = PresetFactory.makePreset(name: "Default", isDefault: true)
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: builtIn.name, preset: builtIn).title
        == builtIn.displayName)
    for name in ["Default", "Preset 3"] {
      let custom = PresetFactory.makePreset(name: name)
      #expect(NowPlayingDisplay.getDisplayInfo(presetName: name, preset: custom).title == name)
    }
  }

  /// Auto-generated "Preset N" names are placeholders too.
  @Test func generatedPresetNameShowsCustomMix() {
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Preset 3").title
        == String(localized: "Custom Mix"))
  }

  @Test func realPresetNameIsTheTitle() {
    #expect(NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").title == "Rainy Night")
  }

  /// Republishes during the mix carry no preset or name, so the mix names itself. It has no
  /// second line, and its artwork is a montage of its sounds like a custom preset's.
  @Test func unsavedMixShowsOnlyItsName() {
    let rain = TestSound(fileName: "test-rain")
    let waves = TestSound(fileName: "test-waves")
    audioManager.sounds = [rain, waves]
    audioManager.defaultSoundOrder = ["test-rain", "test-waves"]
    rain.isSelected = true
    waves.isSelected = true
    PresetManager.shared.setCurrentPreset(nil)
    audioManager.unsavedMix = UnsavedMix(
      name: "Rain + Waves Mix", originSoundFileName: "test-rain",
      soundFileNames: ["test-rain", "test-waves"])

    let info = NowPlayingDisplay.getDisplayInfo(presetName: nil)
    #expect(info.title == "Rain + Waves Mix")
    #expect(info.artist.isEmpty)
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: nil) == nil)
    #expect(NowPlayingDisplay.mixFallbackGlyph() == .composite(audioManager.playingSoundIcons()))
  }

  @Test func missingPresetNameShowsCustomMix() {
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: nil).title == String(localized: "Custom Mix"))
  }

  // MARK: - Artist

  /// A shared preset's creator wins over the sound list.
  @Test func creatorNameIsTheArtist() {
    selectTwoSoundsInOrder()
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night", creatorName: "Ada").artist
        == "Ada"
    )
  }

  @Test func noCreatorAndNoSoundsIsBlankie() {
    audioManager.sounds = []
    #expect(NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").artist == "Blankie")
  }

  /// Sounds list in the preset's own order.
  @Test func noCreatorListsSelectedSoundTitles() {
    selectTwoSoundsInOrder()
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").artist == "test-rain, test-waves")
  }

  // MARK: - Single sound and Quick Mix

  /// A built-in sound's author belongs on the credits screens, so the artist is the app name,
  /// even when the current preset has a creator.
  @Test func singleSoundTitlesItselfWithBlankieArtist() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    audioManager.singleSound = rain

    let info = NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night", creatorName: "Ada")
    #expect(info.title == "test-rain")
    #expect(info.artist == "Blankie")
  }

  /// The caption resolves by title through the credits data.
  @Test func singleSoundPublishesItsCaptionAsArtist() {
    let rain = TestSound(fileName: "Rain")
    audioManager.sounds = [rain]
    audioManager.singleSound = rain

    let caption = rain.localizedSubtitle
    #expect(caption != nil)
    #expect(NowPlayingDisplay.getDisplayInfo(presetName: nil).artist == caption)
  }

  @Test func quickMixTitlesItself() {
    audioManager.isQuickMix = true
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").title
        == String(localized: "Quick Mix"))
  }

  /// Quick Mix keeps the last preset loaded but ignores its creator and membership.
  @Test func quickMixIgnoresPreviousPresetMetadata() {
    selectTwoSoundsInOrder()
    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: "test-rain", isSelected: true, volume: 0.5)],
      creatorName: "Ada")
    PresetManager.shared.setCurrentPreset(preset)
    audioManager.isQuickMix = true

    #expect(NowPlayingDisplay.currentMixSoundTitles().count == 2)
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: preset.name, creatorName: "Ada").artist
        == NowPlayingDisplay.soundNameSummary(NowPlayingDisplay.currentMixSoundTitles()))
    #expect(
      NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada")
        == NowPlayingDisplay.soundNameSummary(NowPlayingDisplay.currentMixSoundTitles()))

    audioManager.sounds = []
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: preset.name, creatorName: "Ada").artist
        == "Blankie")
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada") == nil)
  }

  // MARK: - Widget subtitle

  @Test func widgetSubtitleIsTheCreator() {
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada") == "Ada")
  }

  /// The widget doesn't repeat the synthesized "Blankie" artist.
  @Test func widgetSubtitleIsNilWithNoCreatorAndNoSelection() {
    audioManager.sounds = []
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: nil) == nil)
  }

  /// A built-in single sound has no creator to show.
  @Test func widgetSubtitleIsNilForBuiltInSingle() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    audioManager.singleSound = rain
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada") == nil)
  }

  // MARK: - Progress anchor

  @Test func progressAnchorIsNilWithoutSelectionOrTimer() {
    audioManager.sounds = []
    #expect(!TimerManager.shared.isTimerActive)
    #expect(NowPlayingDisplay.currentProgressAnchor() == nil)
  }

  /// The position poll can't see a sub-second loop wrap.
  @Test func progressAnchorIsNilForSubSecondLoops() {
    let short = TestSound(fileName: "test-rain")
    short.isSelected = true
    audioManager.sounds = [short]
    #expect(!TimerManager.shared.isTimerActive)

    short.stubbedDuration = 0.6
    #expect(NowPlayingDisplay.currentProgressAnchor() == nil)
    short.stubbedDuration = 1.5
    #expect(NowPlayingDisplay.currentProgressAnchor()?.duration == 1.5)
  }
}
