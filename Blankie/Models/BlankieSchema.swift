//
//  BlankieSchema.swift
//  Blankie
//
//  Created by Cody Bromley on 6/15/26.
//

import SwiftData

/// Versioned SwiftData schema + migration plan for the app's persistent store
/// (custom sounds and preset artwork).
///
/// Adopting an explicit plan makes schema changes migrate deterministically
/// instead of relying on SwiftData's automatic inference, which can silently
/// drop a table's rows when two differently-built binaries open the same store
/// (the failure that wiped preset artwork when a TestFlight build was installed
/// over a local debug build).
///
/// **Adding a new version:** snapshot the CURRENT `@Model` definitions into a
/// frozen `BlankieSchemaVN` (copy the types as they are today — do NOT point a
/// historical version at the live model types) before you change them, append
/// it to `BlankieMigrationPlan.schemas`, and add a `MigrationStage` describing
/// the V(N-1) → V(N) transition. V1 below references the live types on purpose:
/// it's the first version and matches the already-shipped store exactly.
nonisolated enum BlankieSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] {
    [CustomSoundData.self, PresetArtwork.self]
  }
}

nonisolated enum BlankieMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [BlankieSchemaV1.self]
  }

  static var stages: [MigrationStage] {
    // No stages yet — V1 is the established baseline. Each future version adds a
    // `.lightweight` or `.custom` stage here for its V(N-1) → V(N) transition.
    []
  }
}
