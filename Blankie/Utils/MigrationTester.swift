//
//  MigrationTester.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/25.
//

import Foundation

/// Test utility to verify UserDefaults migration works correctly
struct MigrationTester {

  /// Run complete migration test - call this from app to test
  static func runCompleteMigrationTest() {
    debugLog("🧪 MigrationTester: Starting complete migration test...")

    resetTestEnvironment()
    setupTestUserData()
    AppDataMigrator.performAllMigrations()
    verifyMigration()

    debugLog("🧪 MigrationTester: Complete migration test finished")
  }

  /// Simulate an existing user's UserDefaults.standard data before migration
  static func setupTestUserData() {
    debugLog("🧪 MigrationTester: Setting up test user data in UserDefaults.standard...")

    // Simulate existing user settings
    UserDefaults.standard.set(0.8, forKey: UserDefaultsKeys.volume)
    UserDefaults.standard.set("light", forKey: UserDefaultsKeys.appearance)
    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.autoPlayOnLaunch)
    UserDefaults.standard.set("en", forKey: UserDefaultsKeys.language)

    // Simulate sound states
    UserDefaults.standard.set(
      [
        ["fileName": "rain", "isSelected": true, "volume": 0.7],
        ["fileName": "waves", "isSelected": true, "volume": 0.9],
        ["fileName": "birds", "isSelected": false, "volume": 1.0],
      ], forKey: "soundState")

    // Simulate default sound order
    UserDefaults.standard.set(
      [
        "rain", "waves", "birds", "storm", "wind",
      ], forKey: "defaultSoundOrder")

    // Simulate individual sound settings
    UserDefaults.standard.set(true, forKey: "rain_isSelected")
    UserDefaults.standard.set(0.7, forKey: "rain_volume")
    UserDefaults.standard.set(true, forKey: "waves_isSelected")
    UserDefaults.standard.set(0.9, forKey: "waves_volume")

    // Simulate timer settings
    UserDefaults.standard.set(2, forKey: "timerLastSelectedHours")
    UserDefaults.standard.set(30, forKey: "timerLastSelectedMinutes")

    // Simulate preset data
    let testPresetData = Data(
      """
      {"id":"12345","name":"Test Preset","isDefault":false,"soundStates":[{"fileName":"rain","isSelected":true,"volume":0.8}]}
      """.utf8)
    UserDefaults.standard.set(testPresetData, forKey: "defaultPreset")

    let testCustomPresetsData = Data(
      """
      [{"id":"67890","name":"Custom Test","isDefault":false,"soundStates":[{"fileName":"waves","isSelected":true,"volume":0.6}]}]
      """.utf8)
    UserDefaults.standard.set(testCustomPresetsData, forKey: "savedPresets")

    UserDefaults.standard.set("12345", forKey: "lastActivePresetID")

    debugLog("✅ MigrationTester: Test user data setup complete")
    logUserDefaults(UserDefaults.standard, label: "BEFORE Migration (standard)")
  }

  /// Verify migration worked correctly
  static func verifyMigration() {
    debugLog("\n🧪 MigrationTester: Verifying migration results...")

    logUserDefaults(UserDefaults.shared, label: "AFTER Migration (shared)")

    // Check if key settings migrated correctly
    let migratedVolume = UserDefaults.shared.double(forKey: UserDefaultsKeys.volume)
    let migratedAutoplay = UserDefaults.shared.bool(forKey: UserDefaultsKeys.autoPlayOnLaunch)
    let migratedSoundState = UserDefaults.shared.array(forKey: "soundState")
    let migratedPresetID = UserDefaults.shared.string(forKey: "lastActivePresetID")

    debugLog("🔍 MigrationTester: Key values after migration:")
    debugLog("  - Volume: \(migratedVolume) (expected: 0.8)")
    debugLog("  - Autoplay: \(migratedAutoplay) (expected: true)")
    debugLog("  - Sound state count: \(migratedSoundState?.count ?? 0) (expected: 3)")
    debugLog("  - Last preset ID: \(migratedPresetID ?? "nil") (expected: 12345)")

    // Verify settings are cleaned up from standard
    let remainingStandard = UserDefaults.standard.object(forKey: UserDefaultsKeys.volume)
    debugLog(
      "  - Remaining in standard: \(remainingStandard != nil ? "❌ Not cleaned up" : "✅ Cleaned up")"
    )

    if migratedVolume == 0.8 && migratedAutoplay && migratedSoundState?.count == 3
      && migratedPresetID == "12345" && remainingStandard == nil
    {
      debugLog("✅ MigrationTester: Migration test PASSED")
    } else {
      debugLog("❌ MigrationTester: Migration test FAILED")
    }
  }

  /// Reset test environment
  static func resetTestEnvironment() {
    debugLog("🧪 MigrationTester: Resetting test environment...")

    // Clear migration flag to allow re-testing
    UserDefaults.shared.removeObject(forKey: "unifiedMigrationCompleted")

    // Clear all test data from both UserDefaults
    let testKeys = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.appearance,
      UserDefaultsKeys.autoPlayOnLaunch,
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
    ]

    for key in testKeys {
      UserDefaults.standard.removeObject(forKey: key)
      UserDefaults.shared.removeObject(forKey: key)
    }

    debugLog("✅ MigrationTester: Test environment reset")
  }

  private static func logUserDefaults(_ defaults: UserDefaults, label: String) {
    debugLog("\n📋 \(label):")
    let dict = defaults.dictionaryRepresentation()
    let relevantKeys = dict.keys.filter { key in
      key.contains("volume") || key.contains("auto") || key.contains("sound")
        || key.contains("preset") || key.contains("timer") || key.contains("rain")
        || key.contains("waves")
    }

    for key in relevantKeys.sorted() {
      debugLog("  - \(key): \(dict[key] ?? "nil")")
    }
  }
}
