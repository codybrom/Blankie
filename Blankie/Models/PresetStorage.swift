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
    print("💾 PresetStorage: Saving \(presets.count) custom presets")

    if let data = try? JSONEncoder().encode(presets) {
      // Add debug logging before saving
      print("Saving presets:")
      presets.forEach { preset in
        print("  - '\(preset.name)':")
        print("    * Order: \(preset.order ?? -1)")
        print(
          "    * Artwork ID: \(preset.artworkId?.uuidString ?? "None")"
        )
        print("    * Creator: \(preset.creatorName ?? "None")")
        print("    * Active sounds:")
        preset.soundStates
          .filter { $0.isSelected }
          .forEach { state in
            print("      - \(state.fileName) (Volume: \(state.volume))")
          }
      }

      // Check data size
      let sizeInMB = Double(data.count) / 1024.0 / 1024.0
      if sizeInMB > 1.0 {
        print("⚠️ PresetStorage: Large data size: \(String(format: "%.2f", sizeInMB)) MB")
      }

      defaults.set(data, forKey: customPresetsKey)
      print("💾 PresetStorage: Custom presets saved successfully")
    }
  }

  static func loadCustomPresets() -> [Preset] {
    print("💾 PresetStorage: Loading custom presets")
    if let data = defaults.data(forKey: customPresetsKey),
      let presets = try? JSONDecoder().decode([Preset].self, from: data)
    {
      print("💾 PresetStorage: Loaded \(presets.count) custom presets")
      // Add debug logging
      presets.forEach { preset in
        print("  - Loaded preset '\(preset.name)':")
        print("    * Order: \(preset.order ?? -1)")
        print(
          "    * Artwork ID: \(preset.artworkId?.uuidString ?? "None")"
        )
        print("    * Creator: \(preset.creatorName ?? "None")")
        print("    * Active sounds:")
        preset.soundStates
          .filter { $0.isSelected }
          .forEach { state in
            print("      - \(state.fileName) (Volume: \(state.volume))")
          }
      }
      return presets
    }
    print("💾 PresetStorage: No custom presets found")
    return []
  }

  static func saveLastActivePresetID(_ id: UUID) {
    // Only save if the ID actually changed
    let currentId = defaults.string(forKey: lastActivePresetIDKey)
    let newIdString = id.uuidString

    guard currentId != newIdString else {
      return  // No change, skip save
    }

    print("💾 PresetStorage: Saving last active preset ID: \(id)")
    defaults.set(newIdString, forKey: lastActivePresetIDKey)
  }

  static func loadLastActivePresetID() -> UUID? {
    print("💾 PresetStorage: Loading last active preset ID")
    guard let idString = defaults.string(forKey: lastActivePresetIDKey),
      let id = UUID(uuidString: idString)
    else {
      print("💾 PresetStorage: No last active preset ID found")
      return nil
    }
    print("💾 PresetStorage: Last active preset ID loaded: \(id)")
    return id
  }
}
