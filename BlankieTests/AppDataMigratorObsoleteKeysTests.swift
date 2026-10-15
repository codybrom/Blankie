//
//  AppDataMigratorObsoleteKeysTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Obsolete-feature keys must be swept on every launch, independent of the
//  one-time unified migration — so a user who migrated on an earlier build
//  still gets stale values (e.g. the removed appearance picker) cleaned up.
//
//  Serialized + class-based: writes real defaults keys; snapshot/restore guards
//  the user's data.
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
    // Simulate a user who already completed the one-time migration…
    UserDefaults.shared.set(true, forKey: "unifiedMigrationCompleted")
    // …but still has stale keys for removed features.
    UserDefaults.shared.set("dark", forKey: "appearanceMode")  // removed in 2.0 (dark-only)
    UserDefaults.standard.set(true, forKey: "hideInactiveSounds")  // removed in 1.1

    AppDataMigrator.performAllMigrations()

    #expect(UserDefaults.shared.object(forKey: "appearanceMode") == nil)
    #expect(UserDefaults.standard.object(forKey: "hideInactiveSounds") == nil)
    // The completion flag is untouched (migration body was correctly skipped).
    #expect(UserDefaults.shared.bool(forKey: "unifiedMigrationCompleted"))
  }
}
