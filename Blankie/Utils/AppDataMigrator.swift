//
//  AppDataMigrator.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/25.
//

import Foundation
import SwiftData
import os

/// Unified migration system for all app data (UserDefaults + SwiftData + App Group)
enum AppDataMigrator {
  private static let migrationCompletedKey = "unifiedMigrationCompleted"

  /// UserDefaults keys for features that no longer exist so stale values don't linger
  private static var obsoleteKeys: [String] {
    var keys = [
      "hideInactiveSounds",  // "Hide Inactive Sounds" feature removed in 1.1
      "appearanceMode",  // Appearance picker removed in 2.0 — app is now dark-only
    ]
    #if os(iOS) || os(visionOS)
      // Autoplay is macOS-only; sweep the legacy keys on iOS so no stale value
      // can sync to a Mac. (macOS migrates them into autoPlayOnLaunchMac.)
      keys.append(UserDefaultsKeys.autoPlayOnLaunch)
      keys.append("alwaysStartPaused")
    #endif
    return keys
  }

  /// Perform one-time migration of all app data
  static func performAllMigrations() {
    // Always purge obsolete keys, independent of the one-time migration below,
    // so users who already migrated on an earlier build still get cleaned up.
    removeObsoleteUserDefaults()

    // Check if unified migration already completed
    guard !UserDefaults.shared.bool(forKey: migrationCompletedKey) else {
      return
    }

    Logger.app.debug("AppDataMigrator: Starting unified app data migration...")

    migrateToAppGroup()
    migrateSwiftDataToAppGroup()
    migrateUserDefaultsToShared()

    // Mark all migrations as completed
    UserDefaults.shared.set(true, forKey: migrationCompletedKey)
    Logger.app.debug("AppDataMigrator: All migrations completed successfully")
  }

  /// Remove UserDefaults entries for features that have been deleted, across
  /// both the standard and shared (app group) suites.
  private static func removeObsoleteUserDefaults() {
    let suites = [UserDefaults.standard, UserDefaults.shared]
    var removedCount = 0

    for key in obsoleteKeys {
      for suite in suites where suite.object(forKey: key) != nil {
        suite.removeObject(forKey: key)
        removedCount += 1
      }
    }

    if removedCount > 0 {
      Logger.app.debug("AppDataMigrator: Removed \(removedCount) obsolete UserDefaults entries")
    }
  }

  /// Migrate UserDefaults to app group (from UserDefaults+AppGroup.swift)
  private static func migrateToAppGroup() {
    guard let groupDefaults = AppGroupConfiguration.sharedDefaults else {
      Logger.app.debug("AppDataMigrator: Unable to access app group defaults")
      return
    }

    let standardDefaults = UserDefaults.standard
    var keysToMigrate = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.accentColor,
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
      UserDefaultsKeys.starredItems,
      "savedSoundStates",

      // Preset storage keys (from PresetStorage.swift)
      "defaultPreset",
      "savedPresets",
      "lastActivePresetID",

      // Legacy keys
      "presets",
      "customArtworkIds",
    ]
    // macOS only: carry the legacy autoplay keys into the shared suite so
    // GlobalSettings can migrate them into autoPlayOnLaunchMac. (iOS purges
    // them via obsoleteKeys.)
    #if os(macOS)
      keysToMigrate.append(UserDefaultsKeys.autoPlayOnLaunch)
      keysToMigrate.append("alwaysStartPaused")
    #endif

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
      Logger.app.debug("AppDataMigrator: Migrated \(migratedCount) values to app group")
    }
  }

  /// Migrate SwiftData to app group (from SwiftDataMigration.swift)
  private static func migrateSwiftDataToAppGroup() {
    guard let appGroupURL = AppGroupConfiguration.dataStoreURL else {
      Logger.app.debug("AppDataMigrator: No app group URL available")
      return
    }

    let fileManager = FileManager.default
    let appGroupStoreExists = fileManager.fileExists(atPath: appGroupURL.path)

    Logger.app.debug("AppDataMigrator: Checking SwiftData migration status...")
    Logger.app.debug("  - App group store exists: \(appGroupStoreExists) at \(appGroupURL.path)")

    // If app group store already exists, no migration needed
    if appGroupStoreExists {
      Logger.app.debug("AppDataMigrator: App group store already exists, no migration needed")
      return
    }

    // Try to find and migrate existing store
    let possibleStoreLocations = getPossibleStoreLocations()
    var migrated = false

    for storeURL in possibleStoreLocations where fileManager.fileExists(atPath: storeURL.path) {
      Logger.app.debug("AppDataMigrator: Found existing store at \(storeURL.path)")

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
            Logger.app.debug("  Copied: \(sourceFile.lastPathComponent)")
          }
        }

        migrated = true
        Logger.app.debug("AppDataMigrator: SwiftData migration completed successfully")
        break
      } catch {
        Logger.app.error("AppDataMigrator: Failed to migrate store: \(error, privacy: .public)")
      }
    }

    if !migrated {
      Logger.app.debug("AppDataMigrator: No existing SwiftData store found to migrate")
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
      Logger.app.debug("AppDataMigrator: No app group documents URL available")
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
      Logger.app.debug("AppDataMigrator: No custom sounds directory to migrate")
      return
    }

    // Create new directory if needed
    do {
      try fileManager.createDirectory(at: newCustomSoundsURL, withIntermediateDirectories: true)
    } catch {
      Logger.app.error(
        "AppDataMigrator: Failed to create custom sounds directory: \(error, privacy: .public)")
      return
    }

    // Migrate all files
    do {
      let files = try fileManager.contentsOfDirectory(
        at: oldCustomSoundsURL, includingPropertiesForKeys: nil
      )

      for file in files {
        let destination = newCustomSoundsURL.appendingPathComponent(file.lastPathComponent)

        // Only migrate if destination doesn't exist
        if !fileManager.fileExists(atPath: destination.path) {
          try fileManager.copyItem(at: file, to: destination)
          Logger.app.debug("AppDataMigrator: Migrated custom sound: \(file.lastPathComponent)")
        }
      }

      Logger.app.debug("AppDataMigrator: Custom sound migration completed")
    } catch {
      Logger.app.error(
        "AppDataMigrator: Failed to migrate custom sounds: \(error, privacy: .public)")
    }
  }

  /// Migrate UserDefaults from standard to shared container
  private static func migrateUserDefaultsToShared() {
    let keysToMigrate = getUserDefaultsKeysToMigrate()
    var migratedCount = 0

    // Migrate primary keys
    migratedCount += migrateKeys(keysToMigrate)

    // Migrate individual sound settings
    migratedCount += migrateSoundSettings()

    Logger.app.debug(
      "AppDataMigrator: UserDefaults migration completed - migrated \(migratedCount) settings")
  }

  /// Get list of keys that need to be migrated
  private static func getUserDefaultsKeysToMigrate() -> [String] {
    var keys = [
      // GlobalSettings keys
      UserDefaultsKeys.volume,
      UserDefaultsKeys.accentColor,
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
      "soundCustomizations",

      // Preset storage keys (from PresetStorage.swift)
      "defaultPreset",
      "savedPresets",
      "lastActivePresetID",
    ]
    // macOS only: carried forward so GlobalSettings can migrate them into
    // autoPlayOnLaunchMac. (iOS purges them via obsoleteKeys.)
    #if os(macOS)
      keys.append(UserDefaultsKeys.autoPlayOnLaunch)
      keys.append("alwaysStartPaused")
    #endif
    return keys
  }

  /// Migrate a list of keys from standard to shared UserDefaults
  private static func migrateKeys(_ keys: [String]) -> Int {
    var migratedCount = 0

    for key in keys {
      if let value = UserDefaults.standard.object(forKey: key) {
        // Only migrate if not already present in shared (preserve existing data)
        if UserDefaults.shared.object(forKey: key) == nil {
          UserDefaults.shared.set(value, forKey: key)
          migratedCount += 1
          Logger.app.debug("AppDataMigrator: Migrated '\(key)'")
        } else {
          Logger.app.debug("AppDataMigrator: Skipped '\(key)' - already exists in shared")
        }
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    return migratedCount
  }

  /// Migrate individual sound settings (volume, selection, hidden state)
  private static func migrateSoundSettings() -> Int {
    var migratedCount = 0
    let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
    let soundKeys = allKeys.filter { key in
      key.hasSuffix("_volume") || key.hasSuffix("_isSelected") || key.hasSuffix("_isHidden")
    }

    for soundKey in soundKeys {
      if let value = UserDefaults.standard.object(forKey: soundKey) {
        // Only migrate if not already present in shared (preserve existing data)
        if UserDefaults.shared.object(forKey: soundKey) == nil {
          UserDefaults.shared.set(value, forKey: soundKey)
          migratedCount += 1
        }
        UserDefaults.standard.removeObject(forKey: soundKey)
      }
    }

    return migratedCount
  }
}
