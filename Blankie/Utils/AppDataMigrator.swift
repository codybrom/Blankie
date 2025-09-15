//
//  AppDataMigrator.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/25.
//

import Foundation
import SwiftData

/// Unified migration system for all app data (UserDefaults + SwiftData + App Group)
struct AppDataMigrator {
  private static let migrationCompletedKey = "unifiedMigrationCompleted"

  /// Perform one-time migration of all app data
  static func performAllMigrations() {
    // Check if unified migration already completed
    guard !UserDefaults.shared.bool(forKey: migrationCompletedKey) else {
      return
    }

    print("🔄 AppDataMigrator: Starting unified app data migration...")

    // Step 1: Migrate to app group container first
    migrateToAppGroup()

    // Step 2: Migrate SwiftData to app group
    migrateSwiftDataToAppGroup()

    // Step 3: Migrate UserDefaults from standard to shared
    migrateUserDefaultsToShared()

    // Mark all migrations as completed
    UserDefaults.shared.set(true, forKey: migrationCompletedKey)
    print("✅ AppDataMigrator: All migrations completed successfully")
  }

  /// Migrate UserDefaults to app group (from UserDefaults+AppGroup.swift)
  private static func migrateToAppGroup() {
    guard let groupDefaults = AppGroupConfiguration.sharedDefaults else {
      print("❌ AppDataMigrator: Unable to access app group defaults")
      return
    }

    let standardDefaults = UserDefaults.standard
    let keysToMigrate = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.appearance,
      UserDefaultsKeys.accentColor,
      UserDefaultsKeys.autoPlayOnLaunch,
      UserDefaultsKeys.hideInactiveSounds,
      UserDefaultsKeys.enableSpatialAudio,
      UserDefaultsKeys.language,
      UserDefaultsKeys.mixWithOthers,
      UserDefaultsKeys.volumeWithOtherAudio,
      UserDefaultsKeys.showSoundNames,
      UserDefaultsKeys.iconSize,
      UserDefaultsKeys.soloModeSoundFileName,
      UserDefaultsKeys.showingListView,
      UserDefaultsKeys.showProgressBorder,
      UserDefaultsKeys.lockPortraitOrientationiOS,
      UserDefaultsKeys.quickMixSoundFileNames,
      "savedSoundStates",

      // Preset storage keys (from PresetStorage.swift)
      "defaultPreset",
      "savedPresets",
      "lastActivePresetID",

      // Legacy keys
      "presets",
      "customArtworkIds",
    ]

    var migratedCount = 0
    for key in keysToMigrate {
      if let value = standardDefaults.object(forKey: key),
        groupDefaults.object(forKey: key) == nil
      {
        groupDefaults.set(value, forKey: key)
        migratedCount += 1
      }
    }

    if migratedCount > 0 {
      groupDefaults.synchronize()
      print("✅ AppDataMigrator: Migrated \(migratedCount) values to app group")
    }
  }

  /// Migrate SwiftData to app group (from SwiftDataMigration.swift)
  private static func migrateSwiftDataToAppGroup() {
    guard let appGroupURL = AppGroupConfiguration.dataStoreURL else {
      print("❌ AppDataMigrator: No app group URL available")
      return
    }

    let fileManager = FileManager.default
    let appGroupStoreExists = fileManager.fileExists(atPath: appGroupURL.path)

    print("📦 AppDataMigrator: Checking SwiftData migration status...")
    print("  - App group store exists: \(appGroupStoreExists) at \(appGroupURL.path)")

    // If app group store already exists, no migration needed
    if appGroupStoreExists {
      print("📦 AppDataMigrator: App group store already exists, no migration needed")
      return
    }

    // Try to find and migrate existing store
    let possibleStoreLocations = getPossibleStoreLocations()
    var migrated = false

    for storeURL in possibleStoreLocations where fileManager.fileExists(atPath: storeURL.path) {
      print("📦 AppDataMigrator: Found existing store at \(storeURL.path)")

      do {
        // Create app group directory if needed
        let appGroupDir = appGroupURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: appGroupDir, withIntermediateDirectories: true)

        // Copy all related files (main db, wal, shm)
        let extensions = ["", "-wal", "-shm"]

        for ext in extensions {
          let sourceFile = URL(fileURLWithPath: storeURL.path + ext)
          let destFile = URL(fileURLWithPath: appGroupURL.path + ext)

          if fileManager.fileExists(atPath: sourceFile.path) {
            try fileManager.copyItem(at: sourceFile, to: destFile)
            print("  ✅ Copied: \(sourceFile.lastPathComponent)")
          }
        }

        migrated = true
        print("📦 AppDataMigrator: SwiftData migration completed successfully")
        break
      } catch {
        print("❌ AppDataMigrator: Failed to migrate store: \(error)")
      }
    }

    if !migrated {
      print("📦 AppDataMigrator: No existing SwiftData store found to migrate")
    }

    // Also migrate custom sound files
    migrateCustomSoundFiles()
  }

  /// Get possible locations for existing SwiftData stores
  private static func getPossibleStoreLocations() -> [URL] {
    let fileManager = FileManager.default
    var locations: [URL] = []

    // Documents directory
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      locations.append(documentsURL.appendingPathComponent("Blankie.sqlite"))
    }

    // Application Support directory
    if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    {
      let bundleId = Bundle.main.bundleIdentifier ?? "com.codybrom.blankie"
      locations.append(
        appSupportURL.appendingPathComponent(bundleId).appendingPathComponent("Blankie.sqlite"))
    }

    return locations
  }

  /// Migrate custom sound files from documents directory to app group
  private static func migrateCustomSoundFiles() {
    guard let appGroupDocsURL = AppGroupConfiguration.documentsURL else {
      print("❌ AppDataMigrator: No app group documents URL available")
      return
    }

    let fileManager = FileManager.default

    // Old location: Documents/CustomSounds
    let oldDocsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let oldCustomSoundsURL = oldDocsURL.appendingPathComponent("CustomSounds")

    // New location: AppGroup/Documents/CustomSounds
    let newCustomSoundsURL = appGroupDocsURL.appendingPathComponent("CustomSounds")

    // Check if old directory exists
    guard fileManager.fileExists(atPath: oldCustomSoundsURL.path) else {
      print("📦 AppDataMigrator: No custom sounds directory to migrate")
      return
    }

    // Create new directory if needed
    do {
      try fileManager.createDirectory(at: newCustomSoundsURL, withIntermediateDirectories: true)
    } catch {
      print("❌ AppDataMigrator: Failed to create custom sounds directory: \(error)")
      return
    }

    // Migrate all files
    do {
      let files = try fileManager.contentsOfDirectory(
        at: oldCustomSoundsURL, includingPropertiesForKeys: nil)

      for file in files {
        let destination = newCustomSoundsURL.appendingPathComponent(file.lastPathComponent)

        // Only migrate if destination doesn't exist
        if !fileManager.fileExists(atPath: destination.path) {
          try fileManager.copyItem(at: file, to: destination)
          print("📦 AppDataMigrator: Migrated custom sound: \(file.lastPathComponent)")
        }
      }

      print("📦 AppDataMigrator: Custom sound migration completed")
    } catch {
      print("❌ AppDataMigrator: Failed to migrate custom sounds: \(error)")
    }
  }

  /// Migrate UserDefaults from standard to shared container
  private static func migrateUserDefaultsToShared() {
    // Define all keys that should be migrated
    let keysToMigrate = [
      // GlobalSettings keys
      UserDefaultsKeys.volume,
      UserDefaultsKeys.appearance,
      UserDefaultsKeys.accentColor,
      UserDefaultsKeys.autoPlayOnLaunch,
      UserDefaultsKeys.hideInactiveSounds,
      UserDefaultsKeys.showSoundNames,
      UserDefaultsKeys.iconSize,
      UserDefaultsKeys.showingListView,
      UserDefaultsKeys.showProgressBorder,
      UserDefaultsKeys.lockPortraitOrientationiOS,
      UserDefaultsKeys.quickMixSoundFileNames,
      UserDefaultsKeys.enableSpatialAudio,
      UserDefaultsKeys.mixWithOthers,
      UserDefaultsKeys.volumeWithOtherAudio,
      UserDefaultsKeys.language,
      UserDefaultsKeys.soloModeSoundFileName,

      // Audio system keys
      "soundState",
      "defaultSoundOrder",

      // Timer keys
      "timerLastSelectedHours",
      "timerLastSelectedMinutes",

      // SoundCustomization keys
      "SoundCustomizations",

      // Preset storage keys (from PresetStorage.swift)
      "defaultPreset",
      "savedPresets",
      "lastActivePresetID",
    ]

    var migratedCount = 0

    // Migrate each key
    for key in keysToMigrate {
      if let value = UserDefaults.standard.object(forKey: key) {
        UserDefaults.shared.set(value, forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        migratedCount += 1
        print("🔄 AppDataMigrator: Migrated '\(key)'")
      }
    }

    // Migrate individual sound settings (volume, selection, hidden state)
    let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
    let soundKeys = allKeys.filter { key in
      key.hasSuffix("_volume") || key.hasSuffix("_isSelected") || key.hasSuffix("_isHidden")
    }

    for soundKey in soundKeys {
      if let value = UserDefaults.standard.object(forKey: soundKey) {
        UserDefaults.shared.set(value, forKey: soundKey)
        UserDefaults.standard.removeObject(forKey: soundKey)
        migratedCount += 1
      }
    }

    print(
      "✅ AppDataMigrator: UserDefaults migration completed - migrated \(migratedCount) settings")
  }
}
