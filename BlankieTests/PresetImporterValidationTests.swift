//
//  PresetImporterValidationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The import pipeline's directory-level gates: required files present, version
//  compatible, and the preset/manifest decode. These run on extracted archive
//  directories (no ZIP, no singletons), so they're pure to exercise.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PresetImporterValidationTests {

  /// A directory missing manifest.json / preset.json is rejected.
  @Test func validateThrowsWhenRequiredFilesMissing() {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(throws: PresetImporter.ImportError.self) {
      try PresetImporter.shared.validateArchiveStructure(at: dir)
    }
  }

  /// A directory with both required files passes.
  @Test func validatePassesWithRequiredFiles() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try ArchiveSupport.writeValidArchiveDir(at: dir, preset: PresetFactory.makePreset())

    try PresetImporter.shared.validateArchiveStructure(at: dir)  // must not throw
  }

  /// A manifest demanding a future minimum version is rejected.
  @Test func validateCompatibilityRejectsFutureMinimum() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let json = """
      {"version":"1.0","blankieVersion":"99.0.0","createdDate":0,\
      "compatibility":{"minimumBlankieVersion":"99.0.0","requiredFeatures":[]}}
      """
    try Data(json.utf8).write(to: dir.appendingPathComponent(PresetArchive.manifestFileName))

    let manifest = try await PresetImporter.shared.readManifest(from: dir)
    #expect(throws: PresetImporter.ImportError.self) {
      try PresetImporter.shared.validateCompatibility(manifest)
    }
  }

  /// A current-floor manifest passes the compatibility gate.
  @Test func validateCompatibilityAcceptsCurrentFloor() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try ArchiveSupport.writeValidArchiveDir(at: dir, preset: PresetFactory.makePreset())

    let manifest = try await PresetImporter.shared.readManifest(from: dir)
    try PresetImporter.shared.validateCompatibility(manifest)  // must not throw
  }

  /// The preset decodes back from the archive with identity AND the full optional
  /// payload intact — artwork/moods/order/view mode are the fields most likely to
  /// silently vanish on a CodingKeys change, and they ride this export path.
  @Test func readPresetRoundTrips() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let artwork = AnimatedArtworkRef(
      source: .custom, loopPath: "loop.mov", previewPath: "preview.png",
      squarePreviewPath: "square.png", preferredAspect: "3:4", bundledIdentifier: "rainforest")
    let original = PresetFactory.makePreset(
      name: "Rainy Night", animatedArtwork: artwork, staticArtworkPath: "static/art.png",
      moods: [.sleep, .relax], viewMode: .list, backgroundBlurRadius: 8.0)
    try ArchiveSupport.writeValidArchiveDir(at: dir, preset: original)

    let decoded = try await PresetImporter.shared.readPreset(from: dir)
    #expect(decoded.id == original.id)
    #expect(decoded.name == "Rainy Night")
    #expect(decoded.soundStates == original.soundStates)
    #expect(decoded.soundOrder == original.soundOrder)
    #expect(decoded.accentColorName == original.accentColorName)
    #expect(decoded.viewMode == original.viewMode)
    #expect(decoded.backgroundBlurRadius == original.backgroundBlurRadius)
    #expect(decoded.moods == original.moods)
    #expect(decoded.animatedArtwork == original.animatedArtwork)
    #expect(decoded.staticArtworkPath == original.staticArtworkPath)
  }

  /// An archive with no sounds directory reports zero custom sounds.
  @Test func countCustomSoundsZeroWhenAbsent() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try ArchiveSupport.writeValidArchiveDir(at: dir, preset: PresetFactory.makePreset())

    let count = await PresetImporter.shared.countCustomSounds(in: dir)
    #expect(count == 0)
  }
}
