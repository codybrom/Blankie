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

  // Raw blobs are copied here when a decode fails, so a corrupt store never
  // silently wipes the user's presets on the next save — they stay recoverable.
  static let defaultPresetBackupKey = "defaultPreset.corruptBackup"
  static let customPresetsBackupKey = "savedPresets.corruptBackup"

  /// Wrapper that turns an undecodable element into `nil` instead of failing the
  /// whole array, so one corrupt preset can't take the rest of the library down.
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
      // Don't overwrite a good stored preset with nothing — skip and log.
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
      // Preserve the raw blob before anything overwrites it, then fall back to a
      // freshly synthesized default rather than crashing or losing it for good.
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
      // Check data size
      let sizeInMB = Double(data.count) / 1024.0 / 1024.0
      if sizeInMB > 1.0 {
        Logger.presets.debug(
          "PresetStorage: Large data size: \(String(format: "%.2f", sizeInMB)) MB")
      }

      defaults.set(data, forKey: customPresetsKey)
      Logger.presets.debug(
        "PresetStorage: Saved \(presets.count) custom presets (\(data.count) bytes)")
    } catch {
      // Encoding the whole library should never fail; if it does, keep the
      // previously stored presets rather than clobbering them with nothing.
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
      // The library failed to decode as a whole. Back up the raw blob so it's
      // recoverable, then salvage every preset that still decodes on its own
      // rather than returning an empty array that the next save would persist.
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
