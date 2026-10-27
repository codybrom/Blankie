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

  /// A legacy duplicate row must not survive to shadow the new artwork.
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

    // Imported refs may retain a square path whose file is missing or corrupt.
    let corruptPath = AnimatedArtworkFileStore.makeRelativePreviewPath(
      for: UUID(), fileExtension: "png")
    try AnimatedArtworkFileStore.writeData(Data([0x01]), to: corruptPath)
    defer { AnimatedArtworkFileStore.removeItemIfExists(relativePath: corruptPath) }
    preset.animatedArtwork?.squarePreviewPath = "missing-square.png"
    #expect(await manager.loadBackgroundImageAsync(for: preset) != nil)
    preset.animatedArtwork?.squarePreviewPath = corruptPath
    #expect(await manager.loadBackgroundImageAsync(for: preset) != nil)
    preset.animatedArtwork?.previewPath = corruptPath
    preset.staticArtworkPath = path
    #expect(await manager.loadBackgroundImageAsync(for: preset) != nil)

    let artworkId = UUID()
    manager.cacheImage(image, for: artworkId)
    preset.artworkId = artworkId
    #expect(await manager.loadBackgroundImageAsync(for: preset) === image)

    preset.artworkId = nil
    preset.animatedArtwork = nil
    #expect(await manager.loadBackgroundImageAsync(for: preset) == nil)
  }

  @Test func widgetArtworkKeepsResolutionAndDownsamplesForSmallTiles() throws {
    let renderer = ImageRenderer(content: Color.red.frame(width: 1200, height: 600))
    renderer.scale = 1
    #if canImport(UIKit)
      let data = try #require(renderer.uiImage?.pngData())
    #else
      let data = try #require(renderer.nsImage?.tiffRepresentation)
    #endif
    let cached = try #require(WidgetArtworkCache.jpegThumbnail(from: data))
    let large = try #require(WidgetArtworkCache.image(from: cached, maxPixelSize: 1024))
    #expect(large.width == 1024)
    #expect(large.height == 512)
    let small = try #require(WidgetArtworkCache.image(from: cached, maxPixelSize: 90))
    #expect(small.width == 90)
    #expect(small.height == 45)
    #expect(WidgetArtworkCache.image(from: Data([0x01]), maxPixelSize: 90) == nil)
  }

  @Test func legacyThumbnailUpgradesAndArtworkRemovalClearsBothCaches() async throws {
    let renderer = ImageRenderer(content: Color.blue.frame(width: 1200, height: 800))
    renderer.scale = 1
    #if canImport(UIKit)
      let image = try #require(renderer.uiImage)
      let data = try #require(image.pngData())
    #else
      let image = try #require(renderer.nsImage)
      let data = try #require(image.tiffRepresentation)
    #endif
    let artworkId = UUID()
    let preset = PresetFactory.makePreset(artworkId: artworkId)
    PresetArtworkManager.shared.cacheImage(image, for: artworkId)
    let key = "preset_thumb_\(preset.id.uuidString)"
    let defaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
    let url = try #require(WidgetArtworkCache.fileURL(for: key))
    defaults.set(
      try #require(WidgetArtworkCache.jpegThumbnail(from: data, maxPixelSize: 132)), forKey: key)
    defer {
      defaults.removeObject(forKey: key)
      try? FileManager.default.removeItem(at: url)
    }

    // A legacy cache hit must not prevent generation of the larger widget file.
    #expect(await PresetManager.shared.cacheThumbnail(for: preset, reloadingWidgets: false))
    let upgraded = try #require(WidgetArtworkCache.image(at: url, maxPixelSize: 1024))
    #expect(upgraded.width == 1024)
    #expect(upgraded.height > 680)
    #expect(await !PresetManager.shared.cacheThumbnail(for: preset, reloadingWidgets: false))

    PresetManager.shared.removeThumbnail(for: preset.id)
    #expect(defaults.data(forKey: key) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  /// Hold the old render at its suspension point, then remove or replace the
  /// artwork before releasing it. The late result must never reach either cache.
  @Test(arguments: [false, true])
  func staleThumbnailCannotOverwriteRemovalOrReplacement(replace: Bool) async throws {
    let renderer = ImageRenderer(content: Color.red.frame(width: 32, height: 32))
    #if canImport(UIKit)
      let image = try #require(renderer.uiImage)
      let data = try #require(image.pngData())
    #else
      let image = try #require(renderer.nsImage)
      let data = try #require(image.tiffRepresentation)
    #endif
    let artworkId = UUID()
    let preset = PresetFactory.makePreset(artworkId: artworkId)
    PresetArtworkManager.shared.cacheImage(image, for: artworkId)
    let manager = PresetManager.shared
    let key = "preset_thumb_\(preset.id.uuidString)"
    let defaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
    let url = try #require(WidgetArtworkCache.fileURL(for: key))
    let started = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    defer {
      started.continuation.finish()
      release.continuation.finish()
      manager.removeThumbnail(for: preset.id)
    }
    let oldRender = Task {
      await manager.cacheThumbnail(
        for: preset, reloadingWidgets: false,
        renderThumbnails: { _ in
          started.continuation.yield(())
          for await _ in release.stream { break }
          return (carPlay: data, widget: data)
        })
    }
    for await _ in started.stream { break }

    let replacement = Data([0x02, 0x03])
    if replace {
      #expect(
        await manager.cacheThumbnail(
          for: preset, force: true, reloadingWidgets: false,
          renderThumbnails: { _ in (carPlay: replacement, widget: replacement) }))
    } else {
      // No cache has been written yet; removal must still cancel the old write.
      manager.removeThumbnail(for: preset.id)
    }
    release.continuation.yield(())
    #expect(await !oldRender.value)
    if replace {
      #expect(defaults.data(forKey: key) == replacement)
      #expect(try Data(contentsOf: url) == replacement)
    } else {
      #expect(defaults.data(forKey: key) == nil)
      #expect(!FileManager.default.fileExists(atPath: url.path))
    }
  }

}
