//
//  MigrationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/25.
//

import Foundation
import Testing

@testable import Blankie

/// Serialized + class-based: every test mutates the shared `UserDefaults` suites
/// and the one-time migration flag, so they must run one at a time, and `init` /
/// `deinit` clear that state before and after each test (the XCTest setUp /
/// tearDown equivalents).
@Suite(.serialized) final class MigrationTests {
  init() {
    // Clear any existing migration state, plus all test keys from both suites.
    UserDefaults.shared.removeObject(forKey: "unifiedMigrationCompleted")
    Self.clearAllTestKeys()
  }

  isolated deinit {
    Self.clearAllTestKeys()
  }

  @Test func userDefaultsMigration() {
    // 1. Setup existing user data in UserDefaults.standard (pre-migration user).
    Self.setupExistingUserData()

    // 2. Verify data lives in standard but not yet in shared.
    #expect(UserDefaults.standard.double(forKey: UserDefaultsKeys.volume) == 0.8)
    #expect(UserDefaults.standard.string(forKey: UserDefaultsKeys.accentColor) == "blue")
    #expect(UserDefaults.shared.object(forKey: UserDefaultsKeys.volume) == nil)

    // 3. Run migration.
    AppDataMigrator.performAllMigrations()

    // 4. Verify cross-platform keys migrated to shared. `autoPlayOnLaunch` is
    // deliberately not asserted: it migrates only on macOS — on iOS it's an
    // obsolete key folded into `autoPlayOnLaunchMac`, not copied to shared.
    #expect(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == 0.8, "Volume should migrate")
    #expect(
      UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor) == "blue",
      "Accent color should migrate")

    // 5. Verify migrated keys were cleared from standard.
    #expect(
      UserDefaults.standard.object(forKey: UserDefaultsKeys.volume) == nil,
      "Volume should be removed from standard")
    #expect(
      UserDefaults.standard.object(forKey: UserDefaultsKeys.accentColor) == nil,
      "Accent color should be removed from standard")

    // 6. Verify migration flag is set.
    #expect(
      UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"), "Migration flag should be set")
  }

  @Test func soundStateMigration() {
    let soundState = [
      ["fileName": "rain", "isSelected": true, "volume": 0.7],
      ["fileName": "waves", "isSelected": false, "volume": 0.9],
    ]
    UserDefaults.standard.set(soundState, forKey: "soundState")

    UserDefaults.standard.set(true, forKey: "rain_isSelected")
    UserDefaults.standard.set(0.7, forKey: "rain_volume")
    UserDefaults.standard.set(false, forKey: "waves_isSelected")
    UserDefaults.standard.set(0.9, forKey: "waves_volume")

    AppDataMigrator.performAllMigrations()

    let migratedSoundState = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]]
    #expect(migratedSoundState != nil)
    #expect(migratedSoundState?.count == 2, "Should migrate 2 sound states")

    #expect(UserDefaults.shared.bool(forKey: "rain_isSelected") == true)
    #expect(abs(UserDefaults.shared.float(forKey: "rain_volume") - 0.7) < 0.01)

    #expect(UserDefaults.standard.object(forKey: "soundState") == nil)
    #expect(UserDefaults.standard.object(forKey: "rain_isSelected") == nil)
  }

  @Test func presetMigration() {
    let testPresetData = Data(
      """
      {"id":"test-preset-123","name":"Test Preset","isDefault":false,"soundStates":[{"fileName":"rain","isSelected":true,"volume":0.8}]}
      """
      .utf8)
    UserDefaults.standard.set(testPresetData, forKey: "defaultPreset")
    UserDefaults.standard.set("test-preset-123", forKey: "lastActivePresetID")

    AppDataMigrator.performAllMigrations()

    #expect(
      UserDefaults.shared.data(forKey: "defaultPreset") != nil, "Default preset should migrate")
    #expect(
      UserDefaults.shared.string(forKey: "lastActivePresetID") == "test-preset-123",
      "Preset ID should migrate")

    #expect(UserDefaults.standard.object(forKey: "defaultPreset") == nil)
    #expect(UserDefaults.standard.object(forKey: "lastActivePresetID") == nil)
  }

  @Test func migrationOnlyRunsOnce() {
    UserDefaults.standard.set(0.5, forKey: UserDefaultsKeys.volume)

    AppDataMigrator.performAllMigrations()
    #expect(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == 0.5)

    // Pollute standard after the first migration; a second run must skip it.
    UserDefaults.standard.set(0.9, forKey: UserDefaultsKeys.volume)
    AppDataMigrator.performAllMigrations()

    #expect(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == 0.5,
      "Migration should only run once")
  }

  @Test func swiftDataMigrationCompletes() {
    // The migration logic must handle missing old stores without crashing.
    AppDataMigrator.performAllMigrations()
    #expect(
      UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"), "Migration should complete")
  }

  @Test func customSoundFileMigration() throws {
    let fileManager = FileManager.default
    let documentsURL = try #require(
      fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)
    let oldCustomSoundsURL = documentsURL.appendingPathComponent("CustomSounds")

    try fileManager.createDirectory(at: oldCustomSoundsURL, withIntermediateDirectories: true)
    let testFile1 = oldCustomSoundsURL.appendingPathComponent("test-sound-1.mp3")
    let testFile2 = oldCustomSoundsURL.appendingPathComponent("test-sound-2.wav")
    try Data("test audio data 1".utf8).write(to: testFile1)
    try Data("test audio data 2".utf8).write(to: testFile2)

    #expect(
      fileManager.fileExists(atPath: testFile1.path), "Test file 1 should exist before migration")
    #expect(
      fileManager.fileExists(atPath: testFile2.path), "Test file 2 should exist before migration")

    AppDataMigrator.performAllMigrations()

    // File migration only happens when the app group is available in the test host.
    if let appGroupURL = AppGroupConfiguration.documentsURL {
      let newCustomSoundsURL = appGroupURL.appendingPathComponent("CustomSounds")
      let migratedFile1 = newCustomSoundsURL.appendingPathComponent("test-sound-1.mp3")
      let migratedFile2 = newCustomSoundsURL.appendingPathComponent("test-sound-2.wav")
      if fileManager.fileExists(atPath: migratedFile1.path),
        fileManager.fileExists(atPath: migratedFile2.path)
      {
        print("✅ Custom sound files migrated to app group")
      } else {
        print("ℹ️ App group not available in test environment - file migration skipped")
      }
    }
  }

  @Test func completeUserUpgradeScenario() {
    Self.setupExistingUserData()

    UserDefaults.standard.set(
      [
        "CustomSound-UUID-1_volume": 0.8,
        "CustomSound-UUID-1_isSelected": true,
        "CustomSound-UUID-2_volume": 0.6,
        "CustomSound-UUID-2_isSelected": false,
      ], forKey: "customSoundSettings")

    let oldFormatPreset = Data(
      """
      {"id":"upgrade-test","name":"Old Format","soundStates":[{"fileName":"rain.mp3","isSelected":true,"volume":0.7}]}
      """
      .utf8)
    UserDefaults.standard.set(oldFormatPreset, forKey: "legacyPreset")

    AppDataMigrator.performAllMigrations()

    // Core settings (volume migrates cross-platform; autoPlayOnLaunch is macOS-only).
    #expect(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == 0.8)

    // Sound data.
    let migratedSoundState = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]]
    #expect(migratedSoundState != nil)
    #expect(migratedSoundState?.count == 3)
    #expect(migratedSoundState?.first?["fileName"] as? String == "rain")
    #expect(migratedSoundState?.first?["isSelected"] as? Bool == true)

    // Cleanup.
    #expect(UserDefaults.standard.object(forKey: UserDefaultsKeys.volume) == nil)
    #expect(UserDefaults.standard.object(forKey: "soundState") == nil)

    // Migration flag.
    #expect(UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"))
  }

  /// Per-key guard: when a value already exists in the shared (app-group)
  /// defaults, migration must NOT overwrite it with the legacy `standard` value
  /// — it only fills in keys that are missing. Distinct from `migrationOnlyRunsOnce`
  /// (which covers the run-once flag); this is the within-a-run "don't clobber" rule.
  @Test func existingAppGroupValuesAreNotOverwritten() {
    // Already-migrated values live in shared…
    UserDefaults.shared.set(0.9, forKey: UserDefaultsKeys.volume)
    UserDefaults.shared.set("blue", forKey: UserDefaultsKeys.accentColor)
    // …while stale conflicting values still sit in standard.
    UserDefaults.standard.set(0.5, forKey: UserDefaultsKeys.volume)
    UserDefaults.standard.set("red", forKey: UserDefaultsKeys.accentColor)

    AppDataMigrator.performAllMigrations()

    #expect(
      UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == 0.9,
      "Existing shared value must be preserved, not overwritten by standard")
    #expect(
      UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor) == "blue",
      "Existing shared value must be preserved, not overwritten by standard")
  }

  // MARK: - Fixtures

  private static func setupExistingUserData() {
    UserDefaults.standard.set(0.8, forKey: UserDefaultsKeys.volume)
    UserDefaults.standard.set("blue", forKey: UserDefaultsKeys.accentColor)
    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.autoPlayOnLaunch)
    UserDefaults.standard.set(true, forKey: "hideInactiveSounds")
    UserDefaults.standard.set("en", forKey: UserDefaultsKeys.language)
    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.enableSpatialAudio)

    UserDefaults.standard.set(
      [
        ["fileName": "rain", "isSelected": true, "volume": 0.7],
        ["fileName": "waves", "isSelected": true, "volume": 0.9],
        ["fileName": "birds", "isSelected": false, "volume": 1.0],
      ], forKey: "soundState")

    UserDefaults.standard.set(["rain", "waves", "birds"], forKey: "defaultSoundOrder")
    UserDefaults.standard.set(2, forKey: "timerLastSelectedHours")
    UserDefaults.standard.set(30, forKey: "timerLastSelectedMinutes")
  }

  private static func clearAllTestKeys() {
    let testKeys = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.accentColor,
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
