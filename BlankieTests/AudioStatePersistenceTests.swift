//
//  AudioStatePersistenceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  saveState() persistence. Quitting during a single sound saves its earlier volume and selection.
//  Serialized: snapshots the real "soundState" key so the user's saved mix is restored.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class AudioStatePersistenceTests {
  private let audioManager = AudioManager.shared
  private let originalSounds: [Sound]
  private let snapshot = DefaultsSnapshot(["soundState", UserDefaultsKeys.singleSoundFileName])

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalSounds = audioManager.sounds
    audioManager.singleSound = nil
    audioManager.isQuickMix = false
    snapshot.clear()
  }
  isolated deinit {
    audioManager.singleSound = nil
    audioManager.isQuickMix = false
    audioManager.sounds = originalSounds
    snapshot.restore()
  }

  private func savedEntry(for fileName: String) -> [String: Any]? {
    let state = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]] ?? []
    return state.first { $0["fileName"] as? String == fileName }
  }

  @Test func saveStatePersistsPreSingleOriginals() {
    let single = TestSound(fileName: "test-single")
    single.volume = 0.4
    single.isSelected = false
    audioManager.sounds = [single]

    audioManager.enterSingleSound(for: single, startPlaying: false)
    // Single sound forces the live values:
    #expect(single.volume == 1.0)
    #expect(single.isSelected)

    audioManager.saveState()

    let entry = savedEntry(for: "test-single")
    #expect(
      entry?["isSelected"] as? Bool == false,
      "earlier selection persisted, not the forced true")
    #expect(
      isClose(entry?["volume"] as? Float ?? -1, 0.4), "earlier volume persisted, not 1.0")
  }

  @Test func saveStatePersistsLiveValuesForNonSingle() {
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    a.volume = 0.6
    audioManager.sounds = [a]

    audioManager.saveState()

    let entry = savedEntry(for: "test-a")
    #expect(entry?["isSelected"] as? Bool == true)
    #expect(isClose(entry?["volume"] as? Float ?? -1, 0.6))
  }

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
