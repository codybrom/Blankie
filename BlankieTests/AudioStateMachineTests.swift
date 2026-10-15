//
//  AudioStateMachineTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Solo, Quick Mix, and music-tag exclusivity as state machines on
//  AudioManager.shared, driven engine-free with TestSounds (no player, so
//  play()/pause() no-op). Synthetic `test-*` file names so the real default
//  preset's sounds never match during preset re-sync.
//
//  Serialized + main-actor, following the existing AudioManagerTests pattern:
//  autoplay off + nothing globally playing, so selecting never starts audio.
//  Each test restores the manager's sounds, mode flags, and touched defaults.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class AudioStateMachineTests {
  private let audioManager = AudioManager.shared
  private let originalSounds: [Sound]
  private let snapshot = DefaultsSnapshot([UserDefaultsKeys.soloModeSoundFileName])
  nonisolated private static let testNames = [
    "test-music-1", "test-music-2", "test-ambient", "test-a", "test-b", "test-solo",
  ]

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalSounds = audioManager.sounds
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
  }

  isolated deinit {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    audioManager.quickMixOriginalStates = []
    audioManager.preQuickMixPreset = nil
    audioManager.sounds = originalSounds
    snapshot.restore()
    for name in Self.testNames {
      UserDefaults.shared.removeObject(forKey: "\(name)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(name)_volume")
    }
  }

  // MARK: - Music exclusivity

  /// A preset holds at most one music sound: selecting a second music sound
  /// turns the first off (radio-button), while non-music sounds are untouched.
  @Test func selectingMusicDeselectsOtherMusic() {
    let m1 = TestSound(fileName: "test-music-1", isMusic: true)
    let m2 = TestSound(fileName: "test-music-2", isMusic: true)
    let ambient = TestSound(fileName: "test-ambient", isMusic: false)
    audioManager.sounds = [m1, m2, ambient]

    m1.isSelected = true
    ambient.isSelected = true
    m2.isSelected = true

    #expect(!m1.isSelected, "the first music sound is deselected when a second is selected")
    #expect(m2.isSelected)
    #expect(ambient.isSelected, "a non-music sound is not affected by music exclusivity")
  }

  // MARK: - Solo mode

  /// Entering solo marks the soloed sound selected at full volume, preserves the
  /// other sounds' selection (they just go silent), and records the mode.
  @Test func enterSoloPreservesOthersAndForcesFullVolume() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    let b = TestSound(fileName: "test-b")
    b.isSelected = true
    let solo = TestSound(fileName: "test-solo")
    solo.volume = 0.6
    audioManager.sounds = [a, b, solo]

    audioManager.enterSoloMode(for: solo, startPlaying: false)

    #expect(audioManager.soloModeSound?.id == solo.id)
    #expect(solo.isSelected)
    #expect(solo.volume == 1.0)
    #expect(a.isSelected, "other sounds keep their selection while soloed")
    #expect(b.isSelected)
    #expect(!audioManager.isGloballyPlaying)
  }

  /// Exiting solo clears the mode and restores the soloed sound's pre-solo
  /// volume and selection.
  @Test func exitSoloRestoresOriginalState() {
    let solo = TestSound(fileName: "test-solo")
    solo.volume = 0.6
    solo.isSelected = false
    audioManager.sounds = [solo]

    audioManager.enterSoloMode(for: solo, startPlaying: false)
    audioManager.exitSoloMode()

    #expect(audioManager.soloModeSound == nil)
    #expect(solo.volume == 0.6)
    #expect(!solo.isSelected)
  }

  // MARK: - Quick Mix

  /// Entering Quick Mix deselects everything; exiting restores each sound's
  /// prior selection and volume.
  @Test func quickMixEntersClearedAndRestoresOnExit() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    a.volume = 0.5
    let b = TestSound(fileName: "test-b")
    audioManager.sounds = [a, b]

    audioManager.enterQuickMix()
    #expect(audioManager.isQuickMix)
    #expect(!a.isSelected, "all sounds are deselected on entering Quick Mix")

    audioManager.exitQuickMix()
    #expect(!audioManager.isQuickMix)
    #expect(a.isSelected, "prior selection is restored on exit")
    #expect(a.volume == 0.5)
  }

  // MARK: - Leaving transient modes

  /// `leaveTransientModes` clears solo — the exit the Siri (`PlayPresetIntent`/
  /// `PlaySoundIntent`) and widget play intents run first, so what they apply
  /// isn't masked by an active solo sound.
  @Test func leaveTransientModesExitsSolo() {
    let solo = TestSound(fileName: "test-solo")
    audioManager.sounds = [solo]
    audioManager.enterSoloMode(for: solo, startPlaying: false)
    #expect(audioManager.soloModeSound != nil)

    audioManager.leaveTransientModes()
    #expect(audioManager.soloModeSound == nil)
  }

  /// `leaveTransientModes` clears Quick Mix, so a later Quick Mix action enters
  /// fresh instead of toggling on top of a still-active mix.
  @Test func leaveTransientModesExitsQuickMix() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    audioManager.sounds = [a]
    audioManager.enterQuickMix()
    #expect(audioManager.isQuickMix)

    audioManager.leaveTransientModes()
    #expect(!audioManager.isQuickMix)
  }
}
