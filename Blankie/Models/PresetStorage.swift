//
//  PresetStorage.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import Foundation
import os

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
    Logger.presets.debug("PresetStorage: Saving \(presets.count) custom presets")

    if let data = try? JSONEncoder().encode(presets) {
      // Check data size
      let sizeInMB = Double(data.count) / 1024.0 / 1024.0
      if sizeInMB > 1.0 {
        Logger.presets.debug(
          "PresetStorage: Large data size: \(String(format: "%.2f", sizeInMB)) MB")
      }

      defaults.set(data, forKey: customPresetsKey)
      Logger.presets.debug(
        "PresetStorage: Saved \(presets.count) custom presets (\(data.count) bytes)")
    }
  }

  static func loadCustomPresets() -> [Preset] {
    Logger.presets.debug("PresetStorage: Loading custom presets")
    if let data = defaults.data(forKey: customPresetsKey),
      let presets = try? JSONDecoder().decode([Preset].self, from: data)
    {
      let summary = presets.map { preset in
        let sounds = preset.soundStates.filter { $0.isSelected }
          .map { "      - \($0.fileName) (Volume: \($0.volume))" }
        return
          ([
            "  - '\(preset.name)':",
            "    * Order: \(preset.order ?? -1)",
            "    * Artwork ID: \(preset.artworkId?.uuidString ?? "None")",
            "    * Creator: \(preset.creatorName ?? "None")",
            "    * Active sounds:",
          ] + sounds).joined(separator: "\n")
      }.joined(separator: "\n")
      Logger.presets.debug("PresetStorage: Loaded \(presets.count) custom presets\n\(summary)")
      return presets
    }
    Logger.presets.debug("PresetStorage: No custom presets found")
    return []
  }

  static func saveLastActivePresetID(_ id: UUID) {
    // Only save if the ID actually changed
    let currentId = defaults.string(forKey: lastActivePresetIDKey)
    let newIdString = id.uuidString

    guard currentId != newIdString else {
      return  // No change, skip save
    }

    Logger.presets.debug("PresetStorage: Saving last active preset ID: \(id)")
    defaults.set(newIdString, forKey: lastActivePresetIDKey)
  }

  static func loadLastActivePresetID() -> UUID? {
    Logger.presets.debug("PresetStorage: Loading last active preset ID")
    guard let idString = defaults.string(forKey: lastActivePresetIDKey),
      let id = UUID(uuidString: idString)
    else {
      Logger.presets.debug("PresetStorage: No last active preset ID found")
      return nil
    }
    Logger.presets.debug("PresetStorage: Last active preset ID loaded: \(id)")
    return id
  }
}
