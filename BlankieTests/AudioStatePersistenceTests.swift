//
//  AudioStatePersistenceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  saveState() persistence, driven engine-free with TestSounds. The headline
//  guard: quitting mid-solo must persist the soloed sound's PRE-solo volume and
//  selection, not the forced solo values — otherwise the user's real mix is
//  overwritten on the next launch.
//
//  Serialized + main-actor (drives AudioManager.shared); snapshots the real
//  "soundState" key so it never corrupts the user's saved mix.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class AudioStatePersistenceTests {
  private let audioManager = AudioManager.shared
  private let originalSounds: [Sound]
  private let snapshot = DefaultsSnapshot(["soundState", UserDefaultsKeys.soloModeSoundFileName])

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalSounds = audioManager.sounds
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    snapshot.clear()
  }
  deinit {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    audioManager.sounds = originalSounds
    snapshot.restore()
  }

  private func savedEntry(for fileName: String) -> [String: Any]? {
    let state = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]] ?? []
    return state.first { $0["fileName"] as? String == fileName }
  }

  @Test func saveStatePersistsPreSoloOriginals() {
    let solo = TestSound(fileName: "test-solo")
    solo.volume = 0.4
    solo.isSelected = false
    audioManager.sounds = [solo]

    audioManager.enterSoloMode(for: solo, startPlaying: false)
    // Solo forces the live values:
    #expect(solo.volume == 1.0)
    #expect(solo.isSelected)

    audioManager.saveState()

    let entry = savedEntry(for: "test-solo")
    #expect(entry?["isSelected"] as? Bool == false, "pre-solo selection persisted, not the forced true")
    #expect(isClose(entry?["volume"] as? Float ?? -1, 0.4), "pre-solo volume persisted, not 1.0")
  }

  @Test func saveStatePersistsLiveValuesForNonSolo() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    a.volume = 0.6
    audioManager.sounds = [a]

    audioManager.saveState()

    let entry = savedEntry(for: "test-a")
    #expect(entry?["isSelected"] as? Bool == true)
    #expect(isClose(entry?["volume"] as? Float ?? -1, 0.6))
  }

  /// saveState is a no-op during Quick Mix so transient mix volumes never persist.
  @Test func saveStateSkippedDuringQuickMix() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    a.volume = 0.5
    audioManager.sounds = [a]
    audioManager.saveState()  // baseline

    audioManager.isQuickMix = true
    a.volume = 0.1  // transient Quick Mix value
    audioManager.saveState()  // must be skipped
    audioManager.isQuickMix = false

    #expect(
      isClose(savedEntry(for: "test-a")?["volume"] as? Float ?? -1, 0.5),
      "Quick Mix transient volume must not persist")
  }
}
