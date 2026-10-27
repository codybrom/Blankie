//
//  BlankieSchema.swift
//  Blankie
//
//  Created by Cody Bromley on 6/15/26.
//

import SwiftData

/// Versioned SwiftData schema and migration plan for custom sounds and preset
/// artwork, so migrations don't depend on SwiftData's automatic inference.
///
/// To add a version, freeze the current `@Model` types into a new `BlankieSchemaVN`
/// before changing them, append it to `schemas`, and add a `MigrationStage`. V1
/// references the live types because it matches the shipped store.
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
    // V1 is the baseline. Each later version adds a `.lightweight` or `.custom` stage.
    []
  }
}
