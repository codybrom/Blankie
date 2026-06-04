//
//  PresetStorage.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import Foundation

struct PresetStorage {
  private static let defaults = UserDefaults.shared

  static let defaultPresetKey = "defaultPreset"
  static let customPresetsKey = "savedPresets"
  static let lastActivePresetIDKey = "lastActivePresetID"

  static func saveDefaultPreset(_ preset: Preset) {
    if let data = try? JSONEncoder().encode(preset) {
      defaults.set(data, forKey: defaultPresetKey)
    }
  }

  static func loadDefaultPreset() -> Preset? {
    guard let data = defaults.data(forKey: defaultPresetKey),
      let preset = try? JSONDecoder().decode(Preset.self, from: data)
    else {
      return nil
    }
    return preset
  }

  static func saveCustomPresets(_ presets: [Preset]) {
    debugLog("PresetStorage: Saving \(presets.count) custom presets", .presets)

    if let data = try? JSONEncoder().encode(presets) {
      // Check data size
      let sizeInMB = Double(data.count) / 1024.0 / 1024.0
      if sizeInMB > 1.0 {
        debugLog("PresetStorage: Large data size: \(String(format: "%.2f", sizeInMB)) MB", .presets)
      }

      defaults.set(data, forKey: customPresetsKey)
      debugLog("PresetStorage: Saved \(presets.count) custom presets (\(data.count) bytes)", .presets)
    }
  }

  static func loadCustomPresets() -> [Preset] {
    debugLog("PresetStorage: Loading custom presets", .presets)
    if let data = defaults.data(forKey: customPresetsKey),
      let presets = try? JSONDecoder().decode([Preset].self, from: data)
    {
      debugLog("PresetStorage: Loaded \(presets.count) custom presets", .presets)
      // Add debug logging
      presets.forEach { preset in
        debugLog("  - Loaded preset '\(preset.name)':", .presets)
        debugLog("    * Order: \(preset.order ?? -1)", .presets)
        debugLog(
          "    * Artwork ID: \(preset.artworkId?.uuidString ?? "None")", .presets
        )
        debugLog("    * Creator: \(preset.creatorName ?? "None")", .presets)
        debugLog("    * Active sounds:", .presets)
        preset.soundStates
          .filter { $0.isSelected }
          .forEach { state in
            debugLog("      - \(state.fileName) (Volume: \(state.volume))", .presets)
          }
      }
      return presets
    }
    debugLog("PresetStorage: No custom presets found", .presets)
    return []
  }

  static func saveLastActivePresetID(_ id: UUID) {
    // Only save if the ID actually changed
    let currentId = defaults.string(forKey: lastActivePresetIDKey)
    let newIdString = id.uuidString

    guard currentId != newIdString else {
      return  // No change, skip save
    }

    debugLog("PresetStorage: Saving last active preset ID: \(id)", .presets)
    defaults.set(newIdString, forKey: lastActivePresetIDKey)
  }

  static func loadLastActivePresetID() -> UUID? {
    debugLog("PresetStorage: Loading last active preset ID", .presets)
    guard let idString = defaults.string(forKey: lastActivePresetIDKey),
      let id = UUID(uuidString: idString)
    else {
      debugLog("PresetStorage: No last active preset ID found", .presets)
      return nil
    }
    debugLog("PresetStorage: Last active preset ID loaded: \(id)", .presets)
    return id
  }
}
