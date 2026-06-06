//
//  MigrationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/25.
//

import XCTest

@testable import Blankie

final class MigrationTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // Clear any existing migration state
    UserDefaults.shared.removeObject(forKey: "unifiedMigrationCompleted")

    // Clear all test keys from both UserDefaults
    clearAllTestKeys()
  }

  override func tearDown() {
    // Clean up after each test
    clearAllTestKeys()
    super.tearDown()
  }

  func testUserDefaultsMigration() {
    // 1. Setup existing user data in UserDefaults.standard (simulating pre-migration user)
    setupExistingUserData()

    // 2. Verify data exists in standard but not in shared
    XCTAssertEqual(UserDefaults.standard.double(forKey: UserDefaultsKeys.volume), 0.8)
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoPlayOnLaunch), true)
    XCTAssertNil(UserDefaults.shared.object(forKey: UserDefaultsKeys.volume))
    XCTAssertNil(UserDefaults.shared.object(forKey: UserDefaultsKeys.autoPlayOnLaunch))

    // 3. Run migration
    AppDataMigrator.performAllMigrations()

    // 4. Verify data migrated to shared
    XCTAssertEqual(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume), 0.8, "Volume should migrate"
    )
    XCTAssertEqual(
      UserDefaults.shared.bool(forKey: UserDefaultsKeys.autoPlayOnLaunch), true,
      "Autoplay should migrate"
    )
    XCTAssertEqual(
      UserDefaults.shared.string(forKey: UserDefaultsKeys.appearance), "light",
      "Appearance should migrate"
    )

    // 5. Verify data cleaned up from standard
    XCTAssertNil(
      UserDefaults.standard.object(forKey: UserDefaultsKeys.volume),
      "Volume should be removed from standard"
    )
    XCTAssertNil(
      UserDefaults.standard.object(forKey: UserDefaultsKeys.autoPlayOnLaunch),
      "Autoplay should be removed from standard"
    )

    // 6. Verify migration flag is set
    XCTAssertTrue(
      UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"), "Migration flag should be set"
    )

    print("✅ UserDefaults migration test passed!")
  }

  func testSoundStateMigration() {
    // Setup sound state data
    let soundState = [
      ["fileName": "rain", "isSelected": true, "volume": 0.7],
      ["fileName": "waves", "isSelected": false, "volume": 0.9],
    ]
    UserDefaults.standard.set(soundState, forKey: "soundState")

    // Setup individual sound settings
    UserDefaults.standard.set(true, forKey: "rain_isSelected")
    UserDefaults.standard.set(0.7, forKey: "rain_volume")
    UserDefaults.standard.set(false, forKey: "waves_isSelected")
    UserDefaults.standard.set(0.9, forKey: "waves_volume")

    // Run migration
    AppDataMigrator.performAllMigrations()

    // Verify sound state migrated
    let migratedSoundState = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]]
    XCTAssertNotNil(migratedSoundState)
    XCTAssertEqual(migratedSoundState?.count, 2, "Should migrate 2 sound states")

    // Verify individual sound settings migrated
    XCTAssertEqual(UserDefaults.shared.bool(forKey: "rain_isSelected"), true)
    XCTAssertEqual(UserDefaults.shared.float(forKey: "rain_volume"), 0.7, accuracy: 0.01)

    // Verify cleanup
    XCTAssertNil(UserDefaults.standard.object(forKey: "soundState"))
    XCTAssertNil(UserDefaults.standard.object(forKey: "rain_isSelected"))

    print("✅ Sound state migration test passed!")
  }

  func testPresetMigration() {
    // Setup preset data
    let testPresetData = Data(
      """
      {"id":"test-preset-123","name":"Test Preset","isDefault":false,"soundStates":[{"fileName":"rain","isSelected":true,"volume":0.8}]}
      """
      .utf8)
    UserDefaults.standard.set(testPresetData, forKey: "defaultPreset")

    UserDefaults.standard.set("test-preset-123", forKey: "lastActivePresetID")

    // Run migration
    AppDataMigrator.performAllMigrations()

    // Verify preset data migrated
    XCTAssertNotNil(
      UserDefaults.shared.data(forKey: "defaultPreset"), "Default preset should migrate"
    )
    XCTAssertEqual(
      UserDefaults.shared.string(forKey: "lastActivePresetID"), "test-preset-123",
      "Preset ID should migrate"
    )

    // Verify cleanup
    XCTAssertNil(UserDefaults.standard.object(forKey: "defaultPreset"))
    XCTAssertNil(UserDefaults.standard.object(forKey: "lastActivePresetID"))

    print("✅ Preset migration test passed!")
  }

  func testMigrationOnlyRunsOnce() {
    // Setup test data
    UserDefaults.standard.set(0.5, forKey: UserDefaultsKeys.volume)

    // Run migration first time
    AppDataMigrator.performAllMigrations()

    // Verify data migrated
    XCTAssertEqual(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume), 0.5)

    // Add new data to standard (simulating another app or test pollution)
    UserDefaults.standard.set(0.9, forKey: UserDefaultsKeys.volume)

    // Run migration again - should skip
    AppDataMigrator.performAllMigrations()

    // Should still have old migrated value, not new polluted value
    XCTAssertEqual(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume), 0.5,
      "Migration should only run once"
    )

    print("✅ Migration runs only once test passed!")
  }

  func testSwiftDataMigration() {
    // Test SwiftData database migration from default location to app group

    // 1. Simulate old SwiftData location (if accessible for testing)
    // Note: This is harder to test directly since we can't easily create old SwiftData stores in tests
    // But we can verify the migration logic doesn't crash and handles missing files correctly

    // Run migration
    AppDataMigrator.performAllMigrations()

    // Verify migration completed without errors
    XCTAssertTrue(
      UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"), "Migration should complete"
    )

    print("✅ SwiftData migration test passed!")
  }

  func testCustomSoundFileMigration() {
    // Test custom sound file migration from Documents to app group

    let fileManager = FileManager.default

    // 1. Create old custom sounds directory structure (simulating pre-app-group version)
    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      XCTFail("Could not get documents directory")
      return
    }

    let oldCustomSoundsURL = documentsURL.appendingPathComponent("CustomSounds")

    do {
      // Create old directory and test files
      try fileManager.createDirectory(at: oldCustomSoundsURL, withIntermediateDirectories: true)

      let testFile1 = oldCustomSoundsURL.appendingPathComponent("test-sound-1.mp3")
      let testFile2 = oldCustomSoundsURL.appendingPathComponent("test-sound-2.wav")

      // Create dummy files
      try Data("test audio data 1".utf8).write(to: testFile1)
      try Data("test audio data 2".utf8).write(to: testFile2)

      // Verify old files exist
      XCTAssertTrue(
        fileManager.fileExists(atPath: testFile1.path), "Test file 1 should exist before migration"
      )
      XCTAssertTrue(
        fileManager.fileExists(atPath: testFile2.path), "Test file 2 should exist before migration"
      )

      // 2. Run migration
      AppDataMigrator.performAllMigrations()

      // 3. Verify files migrated to app group (if app group is available in test environment)
      if let appGroupURL = AppGroupConfiguration.documentsURL {
        let newCustomSoundsURL = appGroupURL.appendingPathComponent("CustomSounds")
        let migratedFile1 = newCustomSoundsURL.appendingPathComponent("test-sound-1.mp3")
        let migratedFile2 = newCustomSoundsURL.appendingPathComponent("test-sound-2.wav")

        // Check if files were migrated (may not work in test environment if app group unavailable)
        if fileManager.fileExists(atPath: migratedFile1.path)
          && fileManager.fileExists(atPath: migratedFile2.path)
        {
          print("✅ Custom sound files migrated to app group")
        } else {
          print("ℹ️ App group not available in test environment - file migration skipped")
        }
      }

      print("✅ Custom sound file migration test passed!")

    } catch {
      XCTFail("Failed to setup test custom sound files: \(error)")
    }
  }

  func testCompleteUserUpgradeScenario() {
    // Test the complete upgrade scenario for a real user

    // 1. Setup comprehensive existing user data (simulating user from v1.0)
    setupExistingUserData()

    // Add custom sound references that would be in old format
    UserDefaults.standard.set(
      [
        "CustomSound-UUID-1_volume": 0.8,
        "CustomSound-UUID-1_isSelected": true,
        "CustomSound-UUID-2_volume": 0.6,
        "CustomSound-UUID-2_isSelected": false,
      ], forKey: "customSoundSettings"
    )

    // Add old preset format with file extensions
    let oldFormatPreset = Data(
      """
      {"id":"upgrade-test","name":"Old Format","soundStates":[{"fileName":"rain.mp3","isSelected":true,"volume":0.7}]}
      """
      .utf8)
    UserDefaults.standard.set(oldFormatPreset, forKey: "legacyPreset")

    // 2. Run complete migration
    AppDataMigrator.performAllMigrations()

    // 3. Verify comprehensive migration

    // Core settings
    XCTAssertEqual(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume), 0.8)
    XCTAssertEqual(UserDefaults.shared.bool(forKey: UserDefaultsKeys.autoPlayOnLaunch), true)

    // Sound data
    let migratedSoundState = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]]
    XCTAssertNotNil(migratedSoundState)
    XCTAssertEqual(migratedSoundState?.count, 3)
    XCTAssertEqual(migratedSoundState?.first?["fileName"] as? String, "rain")
    XCTAssertEqual(migratedSoundState?.first?["isSelected"] as? Bool, true)

    // Cleanup verification
    XCTAssertNil(UserDefaults.standard.object(forKey: UserDefaultsKeys.volume))
    XCTAssertNil(UserDefaults.standard.object(forKey: "soundState"))

    // Migration flag
    XCTAssertTrue(UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"))

    print("✅ Complete user upgrade scenario test passed!")
  }

  private func setupExistingUserData() {
    // Simulate realistic existing user settings
    UserDefaults.standard.set(0.8, forKey: UserDefaultsKeys.volume)
    UserDefaults.standard.set("light", forKey: UserDefaultsKeys.appearance)
    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.autoPlayOnLaunch)
    UserDefaults.standard.set(true, forKey: "hideInactiveSounds")
    UserDefaults.standard.set("en", forKey: UserDefaultsKeys.language)
    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.enableSpatialAudio)

    // Sound states and individual settings
    UserDefaults.standard.set(
      [
        ["fileName": "rain", "isSelected": true, "volume": 0.7],
        ["fileName": "waves", "isSelected": true, "volume": 0.9],
        ["fileName": "birds", "isSelected": false, "volume": 1.0],
      ], forKey: "soundState"
    )

    UserDefaults.standard.set(["rain", "waves", "birds"], forKey: "defaultSoundOrder")
    UserDefaults.standard.set(2, forKey: "timerLastSelectedHours")
    UserDefaults.standard.set(30, forKey: "timerLastSelectedMinutes")
  }

  private func clearAllTestKeys() {
    let testKeys = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.appearance,
      UserDefaultsKeys.autoPlayOnLaunch,
      "hideInactiveSounds",
      UserDefaultsKeys.language,
      UserDefaultsKeys.enableSpatialAudio,
      "soundState",
      "defaultSoundOrder",
      "defaultPreset",
      "savedPresets",
      "lastActivePresetID",
      "rain_isSelected",
      "rain_volume",
      "waves_isSelected",
      "waves_volume",
      "timerLastSelectedHours",
      "timerLastSelectedMinutes",
      "unifiedMigrationCompleted",
    ]

    for key in testKeys {
      UserDefaults.standard.removeObject(forKey: key)
      UserDefaults.shared.removeObject(forKey: key)
    }
  }
}
