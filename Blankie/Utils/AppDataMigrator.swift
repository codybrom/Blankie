//
//  AppDataMigrator.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/25.
//

import Foundation
import SwiftData
import os

/// Migrates app data (UserDefaults, the SwiftData store, custom sound files) into the App Group.
enum AppDataMigrator {
  private static let migrationCompletedKey = "unifiedMigrationCompleted"

  /// UserDefaults keys for features that no longer exist so stale values don't linger
  private static var obsoleteKeys: [String] {
    var keys = [
      "hideInactiveSounds",  // "Hide Inactive Sounds" feature removed in 1.1
      "appearanceMode",  // Appearance picker removed in 2.0 (dark-only)
    ]
    #if os(iOS) || os(visionOS)
      // Autoplay is macOS-only; sweep the legacy keys on iOS so no stale value
      // can sync to a Mac. (macOS migrates them into autoPlayOnLaunchMac.)
      keys.append(UserDefaultsKeys.autoPlayOnLaunch)
      keys.append("alwaysStartPaused")
    #endif
    return keys
  }

  /// Purges obsolete keys, then runs the one-time migration if it hasn't completed.
  static func performAllMigrations() {
    // Always purge obsolete keys, independent of the one-time migration below,
    // so users who already migrated on an earlier build still get cleaned up.
    removeObsoleteUserDefaults()

    guard !UserDefaults.shared.bool(forKey: migrationCompletedKey) else {
      return
    }

    Logger.app.debug("AppDataMigrator: Starting unified app data migration...")

    migrateToAppGroup()
    let storeMigrated = migrateSwiftDataToAppGroup()
    migrateUserDefaultsToShared()

    // A failed store copy leaves the migration unmarked, so the next launch runs
    // it again (every step is idempotent). Store setup stays in memory meanwhile,
    // since any store at the destination would read as a finished copy.
    guard storeMigrated else {
      Logger.app.error("AppDataMigrator: Store migration failed; will retry next launch")
      AppSetup.storeCopyPending = true
      return
    }

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

  /// Copies UserDefaults into the App Group suite.
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
      UserDefaultsKeys.nowPlayingFirst,
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

  /// Copies the SwiftData store into the App Group. Returns false only when an
  /// existing store was found but couldn't be copied.
  @discardableResult
  private static func migrateSwiftDataToAppGroup() -> Bool {
    guard let appGroupURL = AppGroupConfiguration.dataStoreURL else {
      Logger.app.debug("AppDataMigrator: No app group URL available")
      return true
    }

    let fileManager = FileManager.default
    let appGroupStoreExists = fileManager.fileExists(atPath: appGroupURL.path)

    Logger.app.debug("AppDataMigrator: Checking SwiftData migration status...")
    Logger.app.debug("  - App group store exists: \(appGroupStoreExists) at \(appGroupURL.path)")

    if appGroupStoreExists {
      Logger.app.debug("AppDataMigrator: App group store already exists, no migration needed")
      // Still move the sound files, in case an earlier run stopped after the
      // store copy and left rows pointing at unmoved files.
      migrateCustomSoundFiles()
      return true
    }

    let possibleStoreLocations = getPossibleStoreLocations()
    var migrated = false
    var foundStore = false

    for storeURL in possibleStoreLocations where fileManager.fileExists(atPath: storeURL.path) {
      foundStore = true
      Logger.app.debug("AppDataMigrator: Found existing store at \(storeURL.path)")

      do {
        let appGroupDir = appGroupURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: appGroupDir, withIntermediateDirectories: true)

        try copyStoreAtomically(from: storeURL, to: appGroupURL)

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

    migrateCustomSoundFiles()
    return migrated || !foundStore
  }

  /// Copies a store's main, -wal, and -shm files as a set. Each is staged under a
  /// temporary name, then renamed into place, so a failure never leaves a partial
  /// store that the "store exists" check would accept.
  static func copyStoreAtomically(from storeURL: URL, to appGroupURL: URL) throws {
    let fileManager = FileManager.default
    let extensions = ["", "-wal", "-shm"].filter {
      fileManager.fileExists(atPath: storeURL.path + $0)
    }
    let staged = extensions.map { URL(fileURLWithPath: appGroupURL.path + $0 + ".migrating") }
    defer {
      for stagedFile in staged { try? fileManager.removeItem(at: stagedFile) }
    }

    for (ext, stagedFile) in zip(extensions, staged) {
      try? fileManager.removeItem(at: stagedFile)
      try fileManager.copyItem(at: URL(fileURLWithPath: storeURL.path + ext), to: stagedFile)
    }
    // The main file goes last because it's what the "store exists" check looks for.
    for (ext, stagedFile) in zip(extensions, staged).reversed() {
      let destFile = URL(fileURLWithPath: appGroupURL.path + ext)
      try? fileManager.removeItem(at: destFile)  // stale -wal/-shm from a failed run
      try fileManager.moveItem(at: stagedFile, to: destFile)
      Logger.app.debug("  Copied: \(destFile.lastPathComponent)")
    }
  }

  private static func getPossibleStoreLocations() -> [URL] {
    let fileManager = FileManager.default
    var locations: [URL] = []

    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      locations.append(documentsURL.appendingPathComponent("Blankie.sqlite"))
    }

    if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    {
      let bundleId = Bundle.main.bundleIdentifier ?? "com.codybrom.blankie"
      locations.append(
        appSupportURL.appendingPathComponent(bundleId).appendingPathComponent("Blankie.sqlite"))
    }

    return locations
  }

  /// Moves custom sound files from Documents/CustomSounds into the App Group.
  private static func migrateCustomSoundFiles() {
    guard let appGroupDocsURL = AppGroupConfiguration.documentsURL else {
      Logger.app.debug("AppDataMigrator: No app group documents URL available")
      return
    }

    let fileManager = FileManager.default

    let oldDocsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let oldCustomSoundsURL = oldDocsURL.appendingPathComponent("CustomSounds")

    let newCustomSoundsURL = appGroupDocsURL.appendingPathComponent("CustomSounds")

    guard fileManager.fileExists(atPath: oldCustomSoundsURL.path) else {
      Logger.app.debug("AppDataMigrator: No custom sounds directory to migrate")
      return
    }

    do {
      try fileManager.createDirectory(at: newCustomSoundsURL, withIntermediateDirectories: true)
    } catch {
      Logger.app.error(
        "AppDataMigrator: Failed to create custom sounds directory: \(error, privacy: .public)")
      return
    }

    do {
      let files = try fileManager.contentsOfDirectory(
        at: oldCustomSoundsURL, includingPropertiesForKeys: nil
      )

      for file in files {
        let destination = newCustomSoundsURL.appendingPathComponent(file.lastPathComponent)

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

  private static func migrateUserDefaultsToShared() {
    let keysToMigrate = getUserDefaultsKeysToMigrate()
    var migratedCount = 0

    migratedCount += migrateKeys(keysToMigrate)

    migratedCount += migrateSoundSettings()

    Logger.app.debug(
      "AppDataMigrator: UserDefaults migration completed - migrated \(migratedCount) settings")
  }

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
      UserDefaultsKeys.nowPlayingFirst,
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

  private static func migrateKeys(_ keys: [String]) -> Int {
    var migratedCount = 0

    for key in keys {
      if let value = UserDefaults.standard.object(forKey: key) {
        // Never overwrite a value already in the shared suite.
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
        // Never overwrite a value already in the shared suite.
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
