//
//  AudioStateMachineTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Solo, Quick Mix and music exclusivity on AudioManager.shared, engine-free with TestSounds.
//  Synthetic `test-*` names keep the real default preset's sounds from matching on re-sync.
//  Serialized: each test restores the manager's sounds, mode flags and touched defaults.
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

  /// Siri and widget play intents call this first, so an active solo can't mask what they apply.
  @Test func leaveTransientModesExitsSolo() {
    let solo = TestSound(fileName: "test-solo")
    audioManager.sounds = [solo]
    audioManager.enterSoloMode(for: solo, startPlaying: false)
    #expect(audioManager.soloModeSound != nil)

    audioManager.leaveTransientModes()
    #expect(audioManager.soloModeSound == nil)
  }

  /// A later Quick Mix action then enters fresh.
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
