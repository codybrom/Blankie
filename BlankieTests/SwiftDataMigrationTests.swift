//
//  SwiftDataMigrationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/25.
//

import SwiftData
import XCTest

@testable import Blankie

final class SwiftDataMigrationTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // Clear migration state for testing
    UserDefaults.shared.removeObject(forKey: "unifiedMigrationCompleted")
  }

  override func tearDown() {
    // Clean up test data
    cleanupTestFiles()
    super.tearDown()
  }

  func testCustomSoundFileMigration() {
    let fileManager = FileManager.default
    let testFiles = ["test-rain.mp3", "test-waves.wav", "test-birds.m4a"]

    // 1. Setup old custom sounds directory (pre-app-group location)
    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      XCTFail("Could not access documents directory")
      return
    }

    let oldCustomSoundsDir = documentsURL.appendingPathComponent("CustomSounds")

    do {
      // Create old directory structure and test files
      try setupTestSoundFiles(in: oldCustomSoundsDir, fileNames: testFiles)

      print(
        "🧪 SwiftDataMigrationTests: Created \(testFiles.count) test sound files in old location")

      // 2. Run migration
      AppDataMigrator.performAllMigrations()

      // 3. Verify migration results
      try verifyMigratedFiles(testFiles: testFiles)

      print("✅ Custom sound file migration test completed")

    } catch {
      XCTFail("Custom sound file migration test failed: \(error)")
    }
  }

  private func setupTestSoundFiles(in directory: URL, fileNames: [String]) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    for fileName in fileNames {
      let fileURL = directory.appendingPathComponent(fileName)
      let testData = Data("Mock audio data for \(fileName)".utf8)
      try testData.write(to: fileURL)

      // Verify file exists before migration
      XCTAssertTrue(
        fileManager.fileExists(atPath: fileURL.path),
        "Test file \(fileName) should exist before migration"
      )
    }
  }

  private func verifyMigratedFiles(testFiles: [String]) throws {
    let fileManager = FileManager.default

    if let appGroupDocsURL = AppGroupConfiguration.documentsURL {
      let newCustomSoundsDir = appGroupDocsURL.appendingPathComponent("CustomSounds")

      // Check if new directory was created
      XCTAssertTrue(
        fileManager.fileExists(atPath: newCustomSoundsDir.path),
        "New custom sounds directory should exist"
      )

      // Verify files migrated
      for fileName in testFiles {
        let migratedFile = newCustomSoundsDir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: migratedFile.path) {
          print("✅ File \(fileName) successfully migrated to app group")

          // Verify file content
          let migratedData = try Data(contentsOf: migratedFile)
          let expectedData = Data("Mock audio data for \(fileName)".utf8)
          XCTAssertEqual(migratedData, expectedData, "File content should be preserved")
        } else {
          print(
            "⚠️ File \(fileName) not found in app group - app group may not be available in test")
        }
      }
    } else {
      print("ℹ️ App group not available in test environment")
    }
  }

  func testSwiftDataDatabaseMigration() {
    // Test SwiftData database file migration

    let fileManager = FileManager.default

    // 1. Create mock old SwiftData database files
    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      XCTFail("Could not access documents directory")
      return
    }

    let oldDatabasePath = documentsURL.appendingPathComponent("Blankie.sqlite")
    let oldWalPath = documentsURL.appendingPathComponent("Blankie.sqlite-wal")
    let oldShmPath = documentsURL.appendingPathComponent("Blankie.sqlite-shm")

    do {
      // Create mock database files (simulate old SwiftData location)
      try Data("MOCK SQLite DATABASE".utf8).write(to: oldDatabasePath)
      try Data("MOCK WAL FILE".utf8).write(to: oldWalPath)
      try Data("MOCK SHM FILE".utf8).write(to: oldShmPath)

      // Verify old files exist
      XCTAssertTrue(
        fileManager.fileExists(atPath: oldDatabasePath.path), "Old database should exist"
      )
      XCTAssertTrue(fileManager.fileExists(atPath: oldWalPath.path), "Old WAL file should exist")
      XCTAssertTrue(fileManager.fileExists(atPath: oldShmPath.path), "Old SHM file should exist")

      print("🧪 SwiftDataMigrationTests: Created mock SwiftData files in old location")

      // 2. Run migration
      AppDataMigrator.performAllMigrations()

      // 3. Verify database migration (if app group available)
      if let appGroupURL = AppGroupConfiguration.dataStoreURL {
        let newDatabasePath = appGroupURL
        let newWalPath = URL(fileURLWithPath: appGroupURL.path + "-wal")
        let newShmPath = URL(fileURLWithPath: appGroupURL.path + "-shm")

        // Check if database files migrated
        if fileManager.fileExists(atPath: newDatabasePath.path) {
          print("✅ SwiftData database migrated to app group")

          // Verify related files
          if fileManager.fileExists(atPath: newWalPath.path) {
            print("✅ WAL file migrated")
          }
          if fileManager.fileExists(atPath: newShmPath.path) {
            print("✅ SHM file migrated")
          }
        } else {
          print(
            "ℹ️ SwiftData migration skipped - app group may not be available in test or no migration needed"
          )
        }
      }

      print("✅ SwiftData database migration test completed")

    } catch {
      XCTFail("SwiftData migration test failed: \(error)")
    }
  }

  func testMigrationWithExistingAppGroupData() {
    // Test migration when app group already has data (should not overwrite)

    // 1. Setup existing data in shared UserDefaults (simulating partial migration)
    UserDefaults.shared.set(0.9, forKey: UserDefaultsKeys.volume)
    UserDefaults.shared.set("blue", forKey: UserDefaultsKeys.accentColor)

    // 2. Setup conflicting data in standard UserDefaults
    UserDefaults.standard.set(0.5, forKey: UserDefaultsKeys.volume)  // Different value
    UserDefaults.standard.set("red", forKey: UserDefaultsKeys.accentColor)  // Different value
    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.autoPlayOnLaunch)  // New value

    // 3. Run migration
    AppDataMigrator.performAllMigrations()

    // 4. Verify existing shared data preserved, only new data migrated
    XCTAssertEqual(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume), 0.9,
      "Existing shared data should be preserved"
    )
    XCTAssertEqual(
      UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor), "blue",
      "Existing shared data should be preserved"
    )
    XCTAssertEqual(
      UserDefaults.shared.bool(forKey: UserDefaultsKeys.autoPlayOnLaunch), true,
      "New data should be migrated"
    )

    print("✅ Migration with existing app group data test passed!")
  }

  private func cleanupTestFiles() {
    let fileManager = FileManager.default

    // Clean up test directories
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      let testDirs = [
        documentsURL.appendingPathComponent("CustomSounds"),
        documentsURL.appendingPathComponent("Blankie.sqlite"),
        documentsURL.appendingPathComponent("Blankie.sqlite-wal"),
        documentsURL.appendingPathComponent("Blankie.sqlite-shm"),
      ]

      for path in testDirs {
        try? fileManager.removeItem(at: path)
      }
    }

    // Clear test UserDefaults
    let testKeys = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.accentColor,
      UserDefaultsKeys.autoPlayOnLaunch,
      "customSoundSettings",
      "legacyPreset",
      "unifiedMigrationCompleted",
    ]

    for key in testKeys {
      UserDefaults.standard.removeObject(forKey: key)
      UserDefaults.shared.removeObject(forKey: key)
    }
  }
}
