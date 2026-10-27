//
//  AppDataMigratorObsoleteKeysTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Obsolete-feature keys are swept on every launch, even after the one-time migration.
//  Serialized: writes real defaults keys; the snapshot restores the user's values.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) final class AppDataMigratorObsoleteKeysTests {
  private let snapshot = DefaultsSnapshot([
    "appearanceMode", "hideInactiveSounds", "unifiedMigrationCompleted",
  ])

  init() { snapshot.clear() }
  isolated deinit { snapshot.restore() }

  @Test func obsoleteKeysPurgedEvenAfterMigrationCompleted() {
    // Migration already completed, but stale keys for removed features remain.
    UserDefaults.shared.set(true, forKey: "unifiedMigrationCompleted")
    UserDefaults.shared.set("dark", forKey: "appearanceMode")  // removed in 2.0 (dark-only)
    UserDefaults.standard.set(true, forKey: "hideInactiveSounds")  // removed in 1.1

    AppDataMigrator.performAllMigrations()

    #expect(UserDefaults.shared.object(forKey: "appearanceMode") == nil)
    #expect(UserDefaults.standard.object(forKey: "hideInactiveSounds") == nil)
    // The completion flag is untouched (migration body was correctly skipped).
    #expect(UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"))
  }
}
