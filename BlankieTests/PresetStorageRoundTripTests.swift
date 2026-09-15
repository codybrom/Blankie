//
//  PresetStorageRoundTripTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The preset store's static persistence API. Critically: a corrupt blob must
//  never silently wipe the user's library — it's backed up and every preset
//  that still decodes on its own is salvaged.
//
//  Serialized + class-based: writes the real app-group preset keys, so each
//  test snapshots them on entry and restores them on exit.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) final class PresetStorageRoundTripTests {
  private let snapshot = DefaultsSnapshot([
    PresetStorage.defaultPresetKey,
    PresetStorage.customPresetsKey,
    PresetStorage.lastActivePresetIDKey,
    PresetStorage.defaultPresetBackupKey,
    PresetStorage.customPresetsBackupKey,
  ])

  init() { snapshot.clear() }
  isolated deinit { snapshot.restore() }

  @Test func defaultPresetRoundTrips() {
    let preset = PresetFactory.makePreset(name: "My Default", isDefault: true)
    PresetStorage.saveDefaultPreset(preset)
    let loaded = PresetStorage.loadDefaultPreset()
    #expect(loaded?.id == preset.id)
    #expect(loaded?.name == "My Default")
    #expect(loaded?.soundStates == preset.soundStates)
  }

  @Test func customPresetsRoundTrip() {
    let p1 = PresetFactory.makePreset(name: "One")
    let p2 = PresetFactory.makePreset(name: "Two")
    PresetStorage.saveCustomPresets([p1, p2])
    let loaded = PresetStorage.loadCustomPresets()
    #expect(loaded.count == 2)
    #expect(loaded.map(\.name) == ["One", "Two"])
  }

  @Test func lastActiveIDRoundTrips() {
    let id = UUID()
    PresetStorage.saveLastActivePresetID(id)
    #expect(PresetStorage.loadLastActivePresetID() == id)
  }

  @Test func invalidLastActiveIDReturnsNil() {
    UserDefaults.shared.set("not-a-uuid", forKey: PresetStorage.lastActivePresetIDKey)
    #expect(PresetStorage.loadLastActivePresetID() == nil)
  }

  @Test func emptyStoreReturnsDefaults() {
    #expect(PresetStorage.loadCustomPresets().isEmpty)
    #expect(PresetStorage.loadDefaultPreset() == nil)
    #expect(PresetStorage.loadLastActivePresetID() == nil)
  }

  /// A corrupt default-preset blob is backed up and yields nil, not a crash.
  @Test func corruptDefaultPresetIsBackedUp() {
    UserDefaults.shared.set(Data("not json".utf8), forKey: PresetStorage.defaultPresetKey)
    #expect(PresetStorage.loadDefaultPreset() == nil)
    #expect(UserDefaults.shared.data(forKey: PresetStorage.defaultPresetBackupKey) != nil)
  }

  /// The headline resilience guarantee: a custom-preset array with one undecodable
  /// element salvages the valid presets instead of returning an empty library
  /// that the next save would persist.
  @Test func corruptCustomPresetsSalvageValidEntries() throws {
    let valid = PresetFactory.makePreset(name: "Survivor")
    let validObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
    let mixed: [Any] = [validObject, ["bogus": true]]
    let mixedData = try JSONSerialization.data(withJSONObject: mixed)
    UserDefaults.shared.set(mixedData, forKey: PresetStorage.customPresetsKey)

    let loaded = PresetStorage.loadCustomPresets()
    #expect(loaded.count == 1)
    #expect(loaded.first?.name == "Survivor")
    #expect(UserDefaults.shared.data(forKey: PresetStorage.customPresetsBackupKey) != nil)
  }
}
