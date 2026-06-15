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
import os

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

    // Replace every existing record of this type so the saved artwork gets a NEW
    // id. The whole display layer treats artworkId as the artwork's content
    // identity — views reload via `.task(id: artworkId)` and images are
    // memo-cached by id — so reusing the id on an edit left every surface (mixer,
    // Now Playing, lock screen, library thumbnails) showing the stale cached
    // image until relaunch. Delete all matches, not just the first, so a legacy
    // duplicate row can't survive and shadow the new artwork.
    for artwork in try existingArtwork(for: presetId, type: type, in: context) {
      purgeArtwork(artwork, in: context)
    }

    let artwork = PresetArtwork(presetId: presetId, imageData: imageData, type: type)
    context.insert(artwork)
    try context.save()

    // Mirror to an app-group file so the artwork survives a SwiftData store
    // rebuild (the DB row can vanish on a bad migration; the file rehydrates it).
    writeArtworkFile(imageData, for: artwork.id)

    // Warm the cache under the new id so the new image appears immediately.
    if let image = PlatformImage(data: imageData) {
      imageCache[artwork.id] = image
    }
    Logger.presets.debug("PresetArtworkManager: Saved \(type.rawValue) for preset \(presetId)")
    return artwork.id
  }

  /// Load artwork by ID
  func loadArtwork(id: UUID) async -> PlatformImage? {
    // Check cache first
    if let cached = imageCache[id] {
      return cached
    }

    guard let context = modelContext else {
      Logger.presets.error("PresetArtworkManager: No model context")
      return nil
    }

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
        // Back-fill the file mirror for artwork saved before mirroring existed.
        mirrorArtworkFileIfMissing(imageData, for: id)
        return image
      }
    } catch {
      Logger.presets.error(
        "PresetArtworkManager: Failed to load artwork: \(error, privacy: .public)")
    }

    // DB miss (e.g. the store was rebuilt and lost its rows) — rehydrate from
    // the app-group file mirror if one exists.
    if let data = await readArtworkFile(for: id), let image = PlatformImage(data: data) {
      imageCache[id] = image
      Logger.presets.debug("PresetArtworkManager: Rehydrated artwork \(id) from file mirror")
      return image
    }

    return nil
  }

  /// Load raw artwork data by artwork ID
  func loadArtworkData(id: UUID) async -> Data? {
    await Task {
      guard let context = modelContext else {
        Logger.presets.error("PresetArtworkManager: No model context")
        return nil
      }

      let descriptor = FetchDescriptor<PresetArtwork>(
        predicate: #Predicate { $0.id == id }
      )

      do {
        let results = try context.fetch(descriptor)
        if let data = results.first?.imageData {
          return data
        }
      } catch {
        Logger.presets.error(
          "PresetArtworkManager: Failed to load artwork data: \(error, privacy: .public)")
      }
      // Fall back to the app-group file mirror if the DB row is gone.
      return await readArtworkFile(for: id)
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

  /// All artwork rows for a preset of the given type. Filters on the `type`
  /// accessor — which treats a legacy empty `imageType` as `.artwork` — rather
  /// than a raw-string predicate, so artwork saved before `imageType` existed
  /// still matches.
  private func existingArtwork(for presetId: UUID, type: PresetImageType, in context: ModelContext)
    throws -> [PresetArtwork]
  {
    let descriptor = FetchDescriptor<PresetArtwork>(
      predicate: #Predicate { $0.presetId == presetId }
    )
    return try context.fetch(descriptor).filter { $0.type == type }
  }

  /// Delete one artwork row and purge every trace of it — the memory cache and
  /// the app-group file mirror. Does not save; callers batch the save.
  private func purgeArtwork(_ artwork: PresetArtwork, in context: ModelContext) {
    let id = artwork.id
    context.delete(artwork)
    imageCache.removeValue(forKey: id)
    removeArtworkFile(for: id)
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
      purgeArtwork(artwork, in: context)
      try context.save()
      Logger.presets.debug("PresetArtworkManager: Deleted artwork for preset \(presetId)")
    }
  }

  /// Delete specific type of artwork for a preset
  func deleteArtwork(for presetId: UUID, type: PresetImageType) async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    let artworks = try existingArtwork(for: presetId, type: type, in: context)
    for artwork in artworks {
      purgeArtwork(artwork, in: context)
    }

    if !artworks.isEmpty {
      try context.save()
      Logger.presets.debug("PresetArtworkManager: Deleted \(type.rawValue) for preset \(presetId)")
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
    Logger.presets.debug("PresetArtworkManager: Warming artwork cache...")

    // Get current preset
    if let currentPreset = PresetManager.shared.currentPreset {
      await preCacheArtwork(for: currentPreset)
    }

    // Get recent presets (up to 5)
    let recentPresets = PresetManager.shared.getRecentPresets(limit: 5)
    await preCacheArtwork(for: recentPresets)

    Logger.presets.debug("PresetArtworkManager: Cache warming complete")
  }

  /// Clean up orphaned artwork (not referenced by any preset)
  func cleanupOrphanedArtwork() async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    Logger.presets.debug("PresetArtworkManager: Starting orphaned artwork cleanup...")

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

    // Find and delete orphaned artwork. Purging clears the memory cache and the
    // app-group file mirror too, so a stranded mirror can't rehydrate "deleted"
    // artwork via the load-by-id fallback.
    var deletedCount = 0
    for artwork in allArtwork where !referencedArtworkIds.contains(artwork.id) {
      Logger.presets.debug("PresetArtworkManager: Deleting orphaned artwork \(artwork.id)")
      purgeArtwork(artwork, in: context)
      deletedCount += 1
    }

    if deletedCount > 0 {
      try context.save()
      Logger.presets.debug("PresetArtworkManager: Deleted \(deletedCount) orphaned artwork items")
    } else {
      Logger.presets.debug("PresetArtworkManager: No orphaned artwork found")
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
            Logger.presets.debug(
              "PresetArtworkManager: Loaded square preview from Documents: \(squarePath)")
            return image
          }
        }
      }

      // Check Documents directory for 3:4 preview
      if let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath {
        let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
        if FileManager.default.fileExists(atPath: previewURL.path) {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            Logger.presets.debug(
              "PresetArtworkManager: Loaded 3:4 preview from Documents: \(previewPath)")
            return image
          }
        }
      }

      // If not cached, try loading from bundle for bundled resources
      if animatedArtwork.source == .bundled, let bundledId = animatedArtwork.bundledIdentifier {
        let previewName = bundledId
        if let previewURL = Bundle.main.url(forResource: previewName, withExtension: "jpg") {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            Logger.presets.debug(
              "PresetArtworkManager: Loaded preview from bundle: \(previewName).jpg")
            return image
          }
        }
      }

      Logger.presets.debug("PresetArtworkManager: No preview image found for animated artwork")
      return nil
    }
  #endif

  // MARK: - App-group file mirror

  /// Durable file copy of an artwork blob, keyed by artwork id, in the shared
  /// app-group container (like custom sounds — not the per-app container). Lets
  /// artwork survive a SwiftData store rebuild: if the DB row is lost, the load
  /// paths fall back to this file. Returns nil when the app group is
  /// unavailable, in which case the SwiftData blob remains the only copy.
  nonisolated private static func artworkFileURL(for id: UUID) -> URL? {
    AppGroupConfiguration.documentsURL?
      .appendingPathComponent("PresetArtwork", isDirectory: true)
      .appendingPathComponent(id.uuidString)
  }

  private func writeArtworkFile(_ data: Data, for id: UUID) {
    guard let url = Self.artworkFileURL(for: id) else { return }
    // Serialized + off-main via the shared mirror actor so saving artwork never
    // blocks the UI and concurrent writes can't interleave.
    Task { await AppGroupFileMirror.shared.write(data, to: url) }
  }

  /// Back-fill the mirror for artwork saved before mirroring existed.
  private func mirrorArtworkFileIfMissing(_ data: Data, for id: UUID) {
    guard let url = Self.artworkFileURL(for: id),
      !FileManager.default.fileExists(atPath: url.path)
    else { return }
    writeArtworkFile(data, for: id)
  }

  private func readArtworkFile(for id: UUID) async -> Data? {
    guard let url = Self.artworkFileURL(for: id) else { return nil }
    return await AppGroupFileMirror.shared.read(at: url)
  }

  private func removeArtworkFile(for id: UUID) {
    guard let url = Self.artworkFileURL(for: id) else { return }
    Task { await AppGroupFileMirror.shared.remove(at: url) }
  }
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
