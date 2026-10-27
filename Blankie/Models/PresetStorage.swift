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

  // Raw blobs are copied here when a decode fails, so the presets stay
  // recoverable after the next save.
  static let defaultPresetBackupKey = "defaultPreset.corruptBackup"
  static let customPresetsBackupKey = "savedPresets.corruptBackup"

  /// Decodes an undecodable element as `nil` so one corrupt preset doesn't fail
  /// the whole array.
  private struct LossyPreset: Decodable {
    let preset: Preset?
    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      preset = try? container.decode(Preset.self)
    }
  }

  static func saveDefaultPreset(_ preset: Preset) {
    do {
      let data = try JSONEncoder().encode(preset)
      defaults.set(data, forKey: defaultPresetKey)
    } catch {
      // Keep the stored preset.
      Logger.presets.error(
        "PresetStorage: Failed to encode default preset, keeping previous value: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  static func loadDefaultPreset() -> Preset? {
    guard let data = defaults.data(forKey: defaultPresetKey) else {
      return nil
    }
    do {
      return try JSONDecoder().decode(Preset.self, from: data)
    } catch {
      // Back up the raw blob before anything overwrites it. The caller then
      // creates a fresh default.
      Logger.presets.error(
        "PresetStorage: Failed to decode default preset, backing up raw data: \(error.localizedDescription, privacy: .public)"
      )
      defaults.set(data, forKey: defaultPresetBackupKey)
      return nil
    }
  }

  static func saveCustomPresets(_ presets: [Preset]) {
    Logger.presets.debug("PresetStorage: Saving \(presets.count) custom presets")

    do {
      let data = try JSONEncoder().encode(presets)
      let sizeInMB = Double(data.count) / 1024.0 / 1024.0
      if sizeInMB > 1.0 {
        Logger.presets.debug(
          "PresetStorage: Large data size: \(String(format: "%.2f", sizeInMB)) MB")
      }

      defaults.set(data, forKey: customPresetsKey)
      Logger.presets.debug(
        "PresetStorage: Saved \(presets.count) custom presets (\(data.count) bytes)")
    } catch {
      // Keep the previously stored presets.
      Logger.presets.error(
        "PresetStorage: Failed to encode custom presets, keeping previous value: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  static func loadCustomPresets() -> [Preset] {
    Logger.presets.debug("PresetStorage: Loading custom presets")
    guard let data = defaults.data(forKey: customPresetsKey) else {
      Logger.presets.debug("PresetStorage: No custom presets found")
      return []
    }

    do {
      let presets = try JSONDecoder().decode([Preset].self, from: data)
      Logger.presets.debug("PresetStorage: Loaded \(presets.count) custom presets")
      return presets
    } catch {
      // Back up the raw blob, then salvage every preset that decodes on its own
      // so the next save doesn't persist an empty library.
      Logger.presets.error(
        "PresetStorage: Failed to decode custom presets, backing up raw data: \(error.localizedDescription, privacy: .public)"
      )
      defaults.set(data, forKey: customPresetsBackupKey)
      let salvaged = ((try? JSONDecoder().decode([LossyPreset].self, from: data)) ?? [])
        .compactMap(\.preset)
      Logger.presets.error(
        "PresetStorage: Salvaged \(salvaged.count) preset(s) from corrupt data")
      return salvaged
    }
  }

  static func saveLastActivePresetID(_ id: UUID) {
    let currentId = defaults.string(forKey: lastActivePresetIDKey)
    let newIdString = id.uuidString

    guard currentId != newIdString else {
      return
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
