//
//  BlankieSchemaTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//

import SwiftData
import Testing

@testable import Blankie

@Suite struct BlankieSchemaTests {
  /// Pins V1's shape. If a `@Model` in V1 gains, loses, or renames a field, this
  /// fails — forcing a deliberate new schema version plus migration stage rather
  /// than letting V1 silently follow the live model types (which would defeat the
  /// point of an explicit versioned schema). When you intentionally evolve the
  /// models: snapshot the current definitions into a frozen `BlankieSchemaVN`,
  /// add the migration stage, then update the expectation below for the new V1
  /// freeze.
  @Test func v1SchemaMatchesPinnedShape() {
    #expect(BlankieSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))

    let schema = Schema(versionedSchema: BlankieSchemaV1.self)
    let actual = Dictionary(
      uniqueKeysWithValues: schema.entities.map { ($0.name, Set($0.attributesByName.keys)) })

    let expected: [String: Set<String>] = [
      "CustomSoundData": [
        "id", "title", "systemIconName", "fileName", "fileExtension", "dateAdded",
        "randomizeStartPosition", "loopSound", "normalizeAudio", "volumeAdjustment",
        "detectedPeakLevel", "detectedLUFS", "normalizationFactor", "sha256Hash",
        "originalFileName", "creditAuthor", "creditSourceUrl", "creditLicenseType",
        "creditCustomLicenseText", "creditCustomLicenseUrl", "id3Title", "id3Artist",
        "id3Album", "id3Comment", "id3Url", "importedFromPresetId", "importedFromPresetName",
        "moods", "duration",
      ],
      "PresetArtwork": [
        "id", "presetId", "imageType", "imageData", "createdAt", "updatedAt",
      ],
    ]
    #expect(actual == expected)
  }
}
