//
//  SwiftDataMigration.swift
//  Blankie
//
//  Created by Cody Bromley on 7/12/25.
//

import Foundation
import SwiftData

struct SwiftDataMigration {
  /// Migrate SwiftData store from default location to app group container
  static func migrateToAppGroup() {
    guard let appGroupURL = AppGroupConfiguration.dataStoreURL else {
      print("❌ SwiftDataMigration: No app group URL available")
      return
    }

    let fileManager = FileManager.default
    let appGroupStoreExists = fileManager.fileExists(atPath: appGroupURL.path)

    print("📦 SwiftDataMigration: Checking migration status...")
    print("  - App group store exists: \(appGroupStoreExists) at \(appGroupURL.path)")

    // If app group store already exists, no migration needed
    if appGroupStoreExists {
      print("📦 SwiftDataMigration: App group store already exists, no migration needed")
      return
    }

    // Try to find and migrate existing store
    let possibleStoreLocations = getPossibleStoreLocations()
    var migrated = false

    for storeURL in possibleStoreLocations where fileManager.fileExists(atPath: storeURL.path) {
      print("📦 SwiftDataMigration: Found existing store at \(storeURL.path)")

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
        print("📦 SwiftDataMigration: Migration completed successfully")
        break
      } catch {
        print("❌ SwiftDataMigration: Failed to migrate store: \(error)")
      }
    }

    if !migrated {
      print("📦 SwiftDataMigration: No existing store found to migrate")
    }

    // Also migrate custom sound files
    migrateCustomSoundFiles()
  }

  /// Migrate custom sound files from documents directory to app group
  static func migrateCustomSoundFiles() {
    guard let appGroupDocsURL = AppGroupConfiguration.documentsURL else {
      print("❌ SwiftDataMigration: No app group documents URL available")
      return
    }

    let fileManager = FileManager.default

    // Old location: Documents/CustomSounds
    let oldDocsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let oldCustomSoundsURL = oldDocsURL.appendingPathComponent("CustomSounds")

    // New location: AppGroup/Documents/CustomSounds
    let newCustomSoundsURL = appGroupDocsURL.appendingPathComponent("CustomSounds")

    // Check if old directory exists
    if !fileManager.fileExists(atPath: oldCustomSoundsURL.path) {
      print("📦 SwiftDataMigration: No custom sounds directory to migrate")
      return
    }

    // Create new directory if needed
    do {
      try fileManager.createDirectory(at: newCustomSoundsURL, withIntermediateDirectories: true)
    } catch {
      print("❌ SwiftDataMigration: Failed to create custom sounds directory: \(error)")
      return
    }

    // Migrate all files
    do {
      let files = try fileManager.contentsOfDirectory(
        at: oldCustomSoundsURL, includingPropertiesForKeys: nil)
      var migratedCount = 0

      for file in files {
        let destFile = newCustomSoundsURL.appendingPathComponent(file.lastPathComponent)

        // Skip if already exists in destination
        if fileManager.fileExists(atPath: destFile.path) {
          continue
        }

        try fileManager.copyItem(at: file, to: destFile)
        migratedCount += 1
        print("  ✅ Migrated custom sound: \(file.lastPathComponent)")
      }

      if migratedCount > 0 {
        print("📦 SwiftDataMigration: Migrated \(migratedCount) custom sound files")
      }
    } catch {
      print("❌ SwiftDataMigration: Failed to migrate custom sounds: \(error)")
    }
  }

  /// Get all possible locations where SwiftData might have stored data
  private static func getPossibleStoreLocations() -> [URL] {
    var locations: [URL] = []

    #if os(iOS) || os(visionOS)
      locations.append(contentsOf: getiOSStoreLocations())
    #else
      locations.append(contentsOf: getMacOSStoreLocations())
    #endif

    // Also check if there's an existing SwiftData container in the default location
    locations.append(contentsOf: getSwiftDataContainerLocations())

    return locations
  }

  private static func getiOSStoreLocations() -> [URL] {
    var locations: [URL] = []

    let documentsURL = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first!

    let appSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!

    let libraryURL = FileManager.default.urls(
      for: .libraryDirectory,
      in: .userDomainMask
    ).first!

    // Check various possible file names SwiftData might use
    let possibleNames = [
      "default.store",
      "default.sqlite",
      "default.sqlite3",
      "Model.sqlite",
      "Model.sqlite3",
      "\(Bundle.main.bundleIdentifier ?? "Blankie").sqlite",
      "\(Bundle.main.bundleIdentifier ?? "Blankie").store",
    ]

    // Add all combinations
    for name in possibleNames {
      locations.append(documentsURL.appendingPathComponent(name))
      locations.append(appSupportURL.appendingPathComponent(name))
      locations.append(
        libraryURL.appendingPathComponent("Application Support").appendingPathComponent(name))
    }

    return locations
  }

  private static func getMacOSStoreLocations() -> [URL] {
    var locations: [URL] = []

    let appSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!

    let bundleID = Bundle.main.bundleIdentifier ?? "Blankie"
    let appDirectory = appSupportURL.appendingPathComponent(bundleID)

    locations.append(appDirectory.appendingPathComponent("default.store"))
    locations.append(appDirectory.appendingPathComponent("default.sqlite"))

    return locations
  }

  private static func getSwiftDataContainerLocations() -> [URL] {
    var locations: [URL] = []

    let defaultContainer = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first!.appendingPathComponent(".swiftdata")

    if FileManager.default.fileExists(atPath: defaultContainer.path) {
      do {
        let contents = try FileManager.default.contentsOfDirectory(
          at: defaultContainer,
          includingPropertiesForKeys: nil
        )
        locations.append(
          contentsOf: contents.filter {
            $0.pathExtension == "store" || $0.pathExtension == "sqlite"
          })
      } catch {
        print("❌ Error reading .swiftdata directory: \(error)")
      }
    }

    return locations
  }
}
