//
//  NowPlayingDisplayTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/26.
//
//  The backend-neutral display rules: which title and artist the lock screen
//  shows, what the widget's second line is, and when the scrubber has an anchor.
//  Characterization tests — they pin the rules exactly as the MediaPlayer
//  backend shipped them, so a second backend can't quietly drift.
//
//  Serialized + main-actor: drives the AudioManager / PresetManager singletons
//  and GlobalSettings.shared; every touched value is restored in deinit.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class NowPlayingDisplayTests {
  private let audioManager = AudioManager.shared
  private let originalAutoPlay: Bool
  private let originalSounds: [Sound]
  private let originalSolo: Sound?
  private let originalQuickMix: Bool
  private let originalPresets: [Preset]
  private let originalCurrentPreset: Preset?
  nonisolated private static let testNames = ["test-rain", "test-waves"]

  init() {
    originalAutoPlay = GlobalSettings.shared.autoPlayOnLaunch
    originalSounds = audioManager.sounds
    originalSolo = audioManager.soloModeSound
    originalQuickMix = audioManager.isQuickMix
    originalPresets = PresetManager.shared.presets
    originalCurrentPreset = PresetManager.shared.currentPreset
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    AudioManager.shared.resetSounds()
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
  }

  isolated deinit {
    audioManager.soloModeSound = originalSolo
    audioManager.isQuickMix = originalQuickMix
    audioManager.sounds = originalSounds
    PresetManager.shared.setPresets(originalPresets)
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
    GlobalSettings.shared.setAutoPlayOnLaunch(originalAutoPlay)
    for name in Self.testNames {
      UserDefaults.shared.removeObject(forKey: "\(name)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(name)_volume")
    }
  }

  /// Two engine-free sounds, both switched on, inside a preset that fixes their
  /// display order — so the mix's title list is deterministic.
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

  /// "Default" is the internal name of the built-in preset, never a title.
  @Test func defaultPresetNameShowsCustomMix() {
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Default").title
        == String(localized: "Custom Mix")
    )
  }

  /// Auto-generated "Preset N" names are placeholders too.
  @Test func generatedPresetNameShowsCustomMix() {
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Preset 3").title
        == String(localized: "Custom Mix"))
  }

  /// A name the user actually chose is the title, verbatim.
  @Test func realPresetNameIsTheTitle() {
    #expect(NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").title == "Rainy Night")
  }

  /// No preset name at all still gets a title.
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

  /// Nothing to list means the artist line falls back to the app name rather
  /// than going blank.
  @Test func noCreatorAndNoSoundsIsBlankie() {
    audioManager.sounds = []
    #expect(NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").artist == "Blankie")
  }

  /// Without a creator the artist line lists the switched-on sounds, in the
  /// preset's own order.
  @Test func noCreatorListsSelectedSoundTitles() {
    selectTwoSoundsInOrder()
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").artist == "test-rain, test-waves")
  }

  // MARK: - Solo and Quick Mix

  /// Solo mode names the sound itself. A built-in sound's author belongs to the
  /// credits screens, so the artist falls back to the app name — even when the
  /// preset that's still "current" has a creator.
  @Test func soloSoundTitlesItselfWithBlankieArtist() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    audioManager.soloModeSound = rain

    let info = NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night", creatorName: "Ada")
    #expect(info.title == "test-rain")
    #expect(info.artist == "Blankie")
  }

  /// Quick Mix has no preset of its own, so it names itself instead of falling
  /// through to "Custom Mix".
  @Test func quickMixTitlesItself() {
    audioManager.isQuickMix = true
    #expect(
      NowPlayingDisplay.getDisplayInfo(presetName: "Rainy Night").title
        == String(localized: "Quick Mix"))
  }

  // MARK: - Widget subtitle

  /// A creator is a real second line.
  @Test func widgetSubtitleIsTheCreator() {
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada") == "Ada")
  }

  /// No creator and nothing selected means no second line: the widget must not
  /// repeat the synthesized "Blankie" artist.
  @Test func widgetSubtitleIsNilWithNoCreatorAndNoSelection() {
    audioManager.sounds = []
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: nil) == nil)
  }

  /// A soloed built-in sound has no creator to show, so the widget drops the
  /// line rather than echoing the artist's "Blankie".
  @Test func widgetSubtitleIsNilForBuiltInSolo() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    audioManager.soloModeSound = rain
    #expect(NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: "Ada") == nil)
  }

  // MARK: - Progress anchor

  /// Nothing selected and no sleep timer leaves the scrubber indeterminate.
  @Test func progressAnchorIsNilWithoutSelectionOrTimer() {
    audioManager.sounds = []
    #expect(!TimerManager.shared.isTimerActive)
    #expect(NowPlayingDisplay.currentProgressAnchor() == nil)
  }
}
