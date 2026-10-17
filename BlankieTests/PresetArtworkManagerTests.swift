//
//  PresetArtworkManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor
struct PresetArtworkManagerTests {

  /// `saveArtwork` must delete EVERY existing row of the same type, not just the
  /// first, so a legacy duplicate can't survive and shadow the new artwork.
  @Test func saveArtworkReplacesAllDuplicateRows() async throws {
    let container = try ModelContainer(
      for: PresetArtwork.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)

    let presetId = UUID()
    // Two legacy duplicate rows for the same preset + type.
    context.insert(PresetArtwork(presetId: presetId, imageData: Data([0x01]), type: .artwork))
    context.insert(PresetArtwork(presetId: presetId, imageData: Data([0x02]), type: .artwork))
    try context.save()

    let manager = PresetArtworkManager.shared
    manager.setModelContext(context)

    let newData = Data([0x03, 0x04])
    let newId = try await manager.saveArtwork(newData, for: presetId, type: .artwork)

    let rows = try context.fetch(
      FetchDescriptor<PresetArtwork>(predicate: #Predicate { $0.presetId == presetId }))
    #expect(rows.count == 1)
    #expect(rows.first?.id == newId)
    #expect(rows.first?.imageData == newData)
  }
  /// Animation-only presets must have a still background on both platforms.
  /// A square preview wins over portrait, while an explicit photo wins over both.
  @Test func backgroundUsesAnimationStillUnlessPhotoIsSet() async throws {
    let renderer = ImageRenderer(content: Color.red.frame(width: 8, height: 8))
    #if canImport(UIKit)
      let image = try #require(renderer.uiImage)
      let data = try #require(image.pngData())
    #else
      let image = try #require(renderer.nsImage)
      let data = try #require(image.tiffRepresentation)
    #endif
    let path = AnimatedArtworkFileStore.makeRelativePreviewPath(for: UUID(), fileExtension: "png")
    try AnimatedArtworkFileStore.writeData(data, to: path)
    defer { AnimatedArtworkFileStore.removeItemIfExists(relativePath: path) }
    let manager = PresetArtworkManager.shared
    var preset = PresetFactory.makePreset(
      animatedArtwork: AnimatedArtworkRef(
        source: .custom, previewPath: "missing-preview.jpg", squarePreviewPath: path))
    #expect(await manager.loadBackgroundImageAsync(for: preset) != nil)

    // With no square preview, the saved portrait is still a valid fallback.
    preset.animatedArtwork?.squarePreviewPath = nil
    preset.animatedArtwork?.previewPath = path
    #expect(await manager.loadBackgroundImageAsync(for: preset) != nil)

    let artworkId = UUID()
    manager.cacheImage(image, for: artworkId)
    preset.artworkId = artworkId
    #expect(await manager.loadBackgroundImageAsync(for: preset) === image)

    preset.artworkId = nil
    preset.animatedArtwork = nil
    #expect(await manager.loadBackgroundImageAsync(for: preset) == nil)
  }

}
