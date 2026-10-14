//
//  PresetImporterBundledArtworkTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 7/8/26.
//
//  Importing a preset that references a bundled animation must wire its static
//  preview paths onto the preset synchronously — before importArchive re-IDs and
//  stores it. A regression here leaves the imported preset showing placeholder
//  art with the copied preview JPGs orphaned.
//

import Foundation
import Testing

@testable import Blankie

/// Bundled animated-artwork identifiers whose static previews ship in the app
/// bundle. They're copied flat, so the importer resolves `<id>.jpg` and
/// `<id>Square.jpg` at the bundle root, as the picker does.
private nonisolated enum BundledArtworkProbe {
  static let candidateIds = [
    "Abstract1", "Abstract2", "Abstract3", "Abstract4", "Beach", "Bokeh",
    "CityLoop", "GoldenWaves", "GrassWaves", "LavaLamp", "LinenDark", "LinenLight",
    "NeonDrive", "OceanWaves", "PaperPentagons", "Pillows", "RainLoop",
    "RecordPlayer", "Squares", "StreamLoop", "Swirl",
  ]

  static var firstResolvableId: String? {
    candidateIds.first { id in
      Bundle.main.url(forResource: id, withExtension: "jpg") != nil
        && Bundle.main.url(forResource: "\(id)Square", withExtension: "jpg") != nil
    }
  }
}

@Suite struct PresetImporterBundledArtworkTests {

  /// A preset whose `animatedArtwork` is a bundled reference gets both preview
  /// paths set on the `inout` preset synchronously, backed by files on disk, and
  /// keeps its bundled identifier with no loop path. The previews ship in the
  /// app, so a lookup that finds none fails rather than skipping.
  @Test func importSetsBundledPreviewPathsSynchronously() async throws {
    let bundledId = try #require(BundledArtworkProbe.firstResolvableId)

    var preset = PresetFactory.makePreset(
      animatedArtwork: AnimatedArtworkRef(source: .bundled, bundledIdentifier: bundledId))

    let archiveDir = TestSupport.makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: archiveDir)
      AnimatedArtworkFileStore.removeItemIfExists(relativePath: preset.animatedArtwork?.previewPath)
      AnimatedArtworkFileStore.removeItemIfExists(
        relativePath: preset.animatedArtwork?.squarePreviewPath)
    }

    try await PresetImporter.shared.importArtwork(for: &preset, from: archiveDir)

    let artwork = try #require(preset.animatedArtwork)
    #expect(artwork.bundledIdentifier == bundledId)
    #expect(artwork.loopPath == nil)
    #expect(artwork.previewPath != nil)
    #expect(artwork.squarePreviewPath != nil)
    // The referenced previews must actually exist, not just be named.
    #expect(AnimatedArtworkFileStore.fileExists(at: artwork.previewPath))
    #expect(AnimatedArtworkFileStore.fileExists(at: artwork.squarePreviewPath))
  }
}
