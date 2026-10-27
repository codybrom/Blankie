//
//  PendingSaveFlushTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Volume edits save on a 0.1 s debounce, so termination flushes pending saves, including a
//  mix edit still waiting on the preset's coalesced refresh.
//

import Foundation
import Testing

@testable import Blankie

@MainActor
@Suite(.serialized)
struct PendingSaveFlushTests {
  @Test func flushingSavesAPendingGlobalVolumeNow() {
    let settings = GlobalSettings.shared
    let snapshot = DefaultsSnapshot([UserDefaultsKeys.volume])
    let originalVolume = settings.volume
    defer {
      settings.setVolume(originalVolume)
      settings.flushPendingVolumeSave()
      snapshot.restore()
    }

    let target = originalVolume == 0.42 ? 0.43 : 0.42
    settings.setVolume(target)
    settings.flushPendingVolumeSave()

    #expect(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == target)
  }

  @Test func flushingSavesAPendingSoundVolumeNow() throws {
    let sound = TestSound(fileName: "flush-probe-\(UUID().uuidString)")
    let key = "\(sound.fileName)_volume"
    let snapshot = DefaultsSnapshot([key])
    defer { snapshot.restore() }

    sound.volume = 0.31
    sound.flushPendingVolumeSave()

    #expect(abs(UserDefaults.shared.float(forKey: key) - 0.31) < 0.0001)
  }

  /// A mix edit reaches the current preset only after a 100 ms coalesce, so the
  /// flush writes it into the preset itself.
  @Test func flushingSavesAPendingMixEditIntoThePreset() async {
    let sandbox = await SingletonSandbox.make(soundNames: ["flush-mix-a"])
    defer { sandbox.restore() }
    let sound = TestSound(fileName: "flush-mix-a")
    sound.isSelected = true
    sound.volume = 0.5
    sandbox.audioManager.sounds = [sound]
    let preset = PresetFactory.makePreset(
      name: "Flush Mix",
      soundStates: [PresetState(fileName: sound.fileName, isSelected: true, volume: 0.5)],
      soundOrder: [sound.fileName])
    sandbox.presetManager.setPresets([preset])
    sandbox.presetManager.setCurrentPreset(preset)
    sandbox.presetManager.presetStatesApplied = true
    await sandbox.settle()

    sound.volume = 0.3
    flushPendingSaves()

    #expect(sandbox.presetManager.currentPreset?.soundStates.first?.volume == 0.3)
  }
}
