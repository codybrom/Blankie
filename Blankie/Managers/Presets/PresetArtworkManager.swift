//
//  PresetArtworkManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/25.
//

import Foundation
import ImageIO
import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

// Platform-specific image type
#if canImport(UIKit)
  typealias PlatformImage = UIImage
#else
  typealias PlatformImage = NSImage
#endif

@MainActor
class PresetArtworkManager: ObservableObject {
  static let shared = PresetArtworkManager()

  private var modelContext: ModelContext?
  private var imageCache: [UUID: PlatformImage] = [:]
  /// Small downscaled thumbnails for list rows (preset picker), keyed by
  /// "<id>@<maxPixelSize>" so different display sizes don't collide. Kept
  /// separate from `imageCache` so we don't hold full-resolution images for
  /// tiny squircles.
  private var thumbnailCache: [String: PlatformImage] = [:]

  @MainActor
  func setModelContext(_ context: ModelContext) {
    modelContext = context
  }

  /// Synchronously load artwork/background image from cache
  func loadBackgroundImage(for preset: Preset) -> PlatformImage? {
    guard let id = preset.artworkId else { return nil }
    // Return from cache if available
    return imageCache[id]
  }

  /// Asynchronously load artwork/background image (for better performance)
  func loadBackgroundImageAsync(for preset: Preset) async -> PlatformImage? {
    // Try to load from artworkId first
    if let id = preset.artworkId {
      // Check cache first
      if let cached = imageCache[id] {
        return cached
      }

      // Load asynchronously and cache
      if let image = await loadArtwork(id: id) {
        imageCache[id] = image
        return image
      }
    }

    // Fallback: If no artwork is set, try to use animated artwork's preview image
    if preset.artworkId == nil, let animatedArtwork = preset.animatedArtwork {
      #if canImport(UIKit)
        return await loadAnimatedArtworkPreview(animatedArtwork: animatedArtwork, preset: preset)
      #endif
    }

    return nil
  }

  /// Cache an image
  func cacheImage(_ image: PlatformImage, for id: UUID) {
    imageCache[id] = image
  }

  /// Save artwork for a preset
  func saveArtwork(_ imageData: Data, for presetId: UUID, type: PresetImageType = .artwork)
    async throws -> UUID
  {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    // Check if artwork already exists for this preset and type
    let typeString = type.rawValue
    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { artwork in
        artwork.presetId == presetId && artwork.imageType == typeString
      }
    )

    // Replace any existing record so the saved artwork gets a NEW id. The whole
    // display layer treats artworkId as the artwork's content identity — views
    // reload via `.task(id: artworkId)` and images are memo-cached by id — so
    // reusing the id on an edit left every surface (mixer, Now Playing, lock
    // screen, library thumbnails) showing the stale cached image until relaunch.
    if let existingArtwork = try context.fetch(descriptor).first {
      context.delete(existingArtwork)
      imageCache.removeValue(forKey: existingArtwork.id)
    }

    let artwork = PresetArtwork(presetId: presetId, imageData: imageData, type: type)
    context.insert(artwork)
    try context.save()

    // Warm the cache under the new id so the new image appears immediately.
    if let image = PlatformImage(data: imageData) {
      imageCache[artwork.id] = image
    }
    debugLog("PresetArtworkManager: Saved \(type.rawValue) for preset \(presetId)")
    return artwork.id
  }

  /// Load artwork by ID
  func loadArtwork(id: UUID) async -> PlatformImage? {
    // Check cache first
    if let cached = imageCache[id] {
      return cached
    }

    guard let context = modelContext else {
      debugLog("PresetArtworkManager: No model context")
      return nil
    }

    // Run migration lazily when artwork is first accessed
    migrateExistingArtworkIfNeeded()

    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)
      if let imageData = results.first?.imageData,
        let image = PlatformImage(data: imageData)
      {
        // Cache the image
        imageCache[id] = image
        return image
      }
    } catch {
      debugLog("PresetArtworkManager: Failed to load artwork: \(error)")
    }

    return nil
  }

  /// Load artwork for a preset
  func loadArtwork(for presetId: UUID) async throws -> Data? {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { $0.presetId == presetId }
    )

    let results = try context.fetch(descriptor)
    return results.first?.imageData
  }

  /// Load raw artwork data by artwork ID
  func loadArtworkData(id: UUID) async -> Data? {
    await Task {
      guard let context = modelContext else {
        debugLog("PresetArtworkManager: No model context")
        return nil
      }

      let descriptor = FetchDescriptor<PresetArtwork>(
        predicate: #Predicate { $0.id == id }
      )

      do {
        let results = try context.fetch(descriptor)
        return results.first?.imageData
      } catch {
        debugLog("PresetArtworkManager: Failed to load artwork data: \(error)")
        return nil
      }
    }.value
  }

  /// Load a small, downscaled thumbnail of a preset's artwork for list rows.
  /// Decodes straight to `maxPixelSize` via ImageIO (never holding the full
  /// image) and caches the result. `maxPixelSize` is in pixels — pass
  /// points × displayScale.
  func loadThumbnail(id: UUID, maxPixelSize: CGFloat) async -> PlatformImage? {
    let key = "\(id.uuidString)@\(Int(maxPixelSize.rounded()))"
    if let cached = thumbnailCache[key] { return cached }

    guard let data = await loadArtworkData(id: id) else { return nil }

    // Decode off the main actor — ImageIO downsampling reads and resamples the
    // source image, which can stutter scrolling if done on the main thread. The
    // detached task hands back a Sendable CGImage; the PlatformImage wrapper is
    // built back here on the main actor (UIImage/NSImage aren't both Sendable).
    let maxPixel = max(1, maxPixelSize)
    let cgImage = await Task.detached(priority: .userInitiated) {
      Self.downsampledCGImage(data: data, maxPixelSize: maxPixel)
    }.value
    guard let cgImage else { return nil }

    #if canImport(UIKit)
      let thumb = UIImage(cgImage: cgImage)
    #else
      let thumb = NSImage(cgImage: cgImage, size: .zero)
    #endif
    thumbnailCache[key] = thumb
    return thumb
  }

  /// Downsample data to a CGImage no larger than `maxPixelSize` on its longest
  /// edge. Returns a Sendable CGImage so it can
  /// run on a detached task and be wrapped into a `PlatformImage` on the main actor
  nonisolated private static func downsampledCGImage(data: Data, maxPixelSize: CGFloat) -> CGImage?
  {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
      return nil
    }
    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
  }

  /// Delete artwork for a preset
  func deleteArtwork(for presetId: UUID) async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { $0.presetId == presetId }
    )

    if let artwork = try context.fetch(descriptor).first {
      context.delete(artwork)
      try context.save()
      debugLog("PresetArtworkManager: Deleted artwork for preset \(presetId)")
    }
  }

  /// Delete specific type of artwork for a preset
  func deleteArtwork(for presetId: UUID, type: PresetImageType) async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    let typeString = type.rawValue
    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { artwork in
        artwork.presetId == presetId && artwork.imageType == typeString
      }
    )

    let artworks = try context.fetch(descriptor)
    for artwork in artworks {
      context.delete(artwork)
      // Remove from cache
      imageCache.removeValue(forKey: artwork.id)
    }

    if !artworks.isEmpty {
      try context.save()
      debugLog("PresetArtworkManager: Deleted \(type.rawValue) for preset \(presetId)")
    }
  }

  /// Pre-cache artwork for a preset (loads into memory cache)
  func preCacheArtwork(for preset: Preset) async {
    // Cache main artwork if exists
    if let artworkId = preset.artworkId {
      _ = await loadArtwork(id: artworkId)
    }
  }

  /// Pre-cache artwork for multiple presets
  func preCacheArtwork(for presets: [Preset]) async {
    for preset in presets {
      await preCacheArtwork(for: preset)
    }
  }

  /// Warm cache on app launch with current and recent presets
  func warmCache() async {
    debugLog("PresetArtworkManager: Warming artwork cache...")

    // Get current preset
    if let currentPreset = PresetManager.shared.currentPreset {
      await preCacheArtwork(for: currentPreset)
    }

    // Get recent presets (up to 5)
    let recentPresets = PresetManager.shared.getRecentPresets(limit: 5)
    await preCacheArtwork(for: recentPresets)

    debugLog("PresetArtworkManager: Cache warming complete")
  }

  /// Clean up orphaned artwork (not referenced by any preset)
  func cleanupOrphanedArtwork() async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    debugLog("PresetArtworkManager: Starting orphaned artwork cleanup...")

    // Get all preset IDs and their artwork references
    let presets = PresetManager.shared.presets
    var referencedArtworkIds = Set<UUID>()

    for preset in presets {
      if let artworkId = preset.artworkId {
        referencedArtworkIds.insert(artworkId)
      }
    }

    // Fetch all artwork
    let descriptor = FetchDescriptor<PresetArtwork>()
    let allArtwork = try context.fetch(descriptor)

    // Find and delete orphaned artwork
    var deletedCount = 0
    for artwork in allArtwork where !referencedArtworkIds.contains(artwork.id) {
      debugLog("PresetArtworkManager: Deleting orphaned artwork \(artwork.id)")
      context.delete(artwork)
      deletedCount += 1

      // Also remove from cache
      imageCache.removeValue(forKey: artwork.id)
    }

    if deletedCount > 0 {
      try context.save()
      debugLog("PresetArtworkManager: Deleted \(deletedCount) orphaned artwork items")
    } else {
      debugLog("PresetArtworkManager: No orphaned artwork found")
    }
  }

  private var hasMigrationRun = false

  /// Migrate existing artwork records to have proper imageType values
  /// Only runs when artwork is actually being accessed, not during cold start
  private func migrateExistingArtworkIfNeeded() {
    guard !hasMigrationRun,
      let context = modelContext
    else { return }

    hasMigrationRun = true

    Task {
      do {
        let descriptor = FetchDescriptor<PresetArtwork>()
        let allArtwork = try context.fetch(descriptor)

        var migratedCount = 0
        for artwork in allArtwork where artwork.imageType.isEmpty {
          artwork.imageType = PresetImageType.artwork.rawValue
          artwork.updatedAt = Date()
          migratedCount += 1
        }

        if migratedCount > 0 {
          try context.save()
          debugLog(
            "PresetArtworkManager: Migrated \(migratedCount) artwork records to have imageType")
        }
      } catch {
        debugLog("PresetArtworkManager: Lazy migration failed: \(error)")
        hasMigrationRun = false  // Allow retry later
      }
    }
  }

  #if canImport(UIKit)
    /// Load preview image from animated artwork as fallback
    /// Uses square preview for now playing artwork, or falls back to 3:4 preview
    private func loadAnimatedArtworkPreview(animatedArtwork: AnimatedArtworkRef, preset: Preset)
      async -> PlatformImage?
    {
      // Try square preview first (for now playing artwork)
      if let squarePath = animatedArtwork.squarePreviewPath {
        let squareURL = AnimatedArtworkFileStore.absoluteURL(for: squarePath)
        if FileManager.default.fileExists(atPath: squareURL.path) {
          if let image = UIImage(contentsOfFile: squareURL.path) {
            debugLog("PresetArtworkManager: Loaded square preview from Documents: \(squarePath)")
            return image
          }
        }
      }

      // Check Documents directory for 3:4 preview
      if let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath {
        let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
        if FileManager.default.fileExists(atPath: previewURL.path) {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            debugLog("PresetArtworkManager: Loaded 3:4 preview from Documents: \(previewPath)")
            return image
          }
        }
      }

      // If not cached, try loading from bundle for bundled resources
      if animatedArtwork.source == .bundled, let bundledId = animatedArtwork.bundledIdentifier {
        let previewName = bundledId
        if let previewURL = Bundle.main.url(forResource: previewName, withExtension: "jpg") {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            debugLog("PresetArtworkManager: Loaded preview from bundle: \(previewName).jpg")
            return image
          }
        }
      }

      debugLog("PresetArtworkManager: No preview image found for animated artwork")
      return nil
    }
  #endif
}

enum PresetArtworkError: LocalizedError {
  case noModelContext
  case artworkNotFound

  var errorDescription: String? {
    switch self {
    case .noModelContext:
      return "Model context not initialized"
    case .artworkNotFound:
      return "Artwork not found"
    }
  }
}
