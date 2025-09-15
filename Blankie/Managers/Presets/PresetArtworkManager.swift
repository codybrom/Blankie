//
//  PresetArtworkManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/25.
//

import Foundation
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

  @MainActor
  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
  }

  /// Synchronously load background image from cache
  func loadBackgroundImage(for preset: Preset) -> PlatformImage? {
    let imageId: UUID?

    if preset.useArtworkAsBackground ?? false {
      imageId = preset.artworkId
    } else {
      imageId = preset.backgroundImageId
    }

    guard let id = imageId else { return nil }

    // Return from cache if available
    return imageCache[id]
  }

  /// Asynchronously load background image (for better performance)
  func loadBackgroundImageAsync(for preset: Preset) async -> PlatformImage? {
    let imageId: UUID?

    if preset.useArtworkAsBackground ?? false {
      imageId = preset.artworkId
    } else {
      imageId = preset.backgroundImageId
    }

    guard let id = imageId else { return nil }

    // Check cache first
    if let cached = imageCache[id] {
      return cached
    }

    // Load asynchronously and cache
    if let image = await loadArtwork(id: id) {
      imageCache[id] = image
      return image
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

    if let existingArtwork = try context.fetch(descriptor).first {
      // Update existing artwork
      existingArtwork.imageData = imageData
      existingArtwork.updatedAt = Date()
      try context.save()
      print("📸 PresetArtworkManager: Updated \(type.rawValue) for preset \(presetId)")
      return existingArtwork.id
    } else {
      // Create new artwork
      let artwork = PresetArtwork(presetId: presetId, imageData: imageData, type: type)
      context.insert(artwork)
      try context.save()
      print("📸 PresetArtworkManager: Saved new \(type.rawValue) for preset \(presetId)")
      return artwork.id
    }
  }

  /// Load artwork by ID
  func loadArtwork(id: UUID) async -> PlatformImage? {
    // Check cache first
    if let cached = imageCache[id] {
      return cached
    }

    guard let context = modelContext else {
      print("❌ PresetArtworkManager: No model context")
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
      print("❌ PresetArtworkManager: Failed to load artwork: \(error)")
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
        print("❌ PresetArtworkManager: No model context")
        return nil
      }

      let descriptor = FetchDescriptor<PresetArtwork>(
        predicate: #Predicate { $0.id == id }
      )

      do {
        let results = try context.fetch(descriptor)
        return results.first?.imageData
      } catch {
        print("❌ PresetArtworkManager: Failed to load artwork data: \(error)")
        return nil
      }
    }.value
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
      print("📸 PresetArtworkManager: Deleted artwork for preset \(presetId)")
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
      print("📸 PresetArtworkManager: Deleted \(type.rawValue) for preset \(presetId)")
    }
  }

  /// Pre-cache artwork for a preset (loads into memory cache)
  func preCacheArtwork(for preset: Preset) async {
    // Cache main artwork if exists
    if let artworkId = preset.artworkId {
      _ = await loadArtwork(id: artworkId)
    }

    // Cache background image if different from artwork
    if !(preset.useArtworkAsBackground ?? false),
      let backgroundId = preset.backgroundImageId
    {
      _ = await loadArtwork(id: backgroundId)
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
    print("📸 PresetArtworkManager: Warming artwork cache...")

    // Get current preset
    if let currentPreset = PresetManager.shared.currentPreset {
      await preCacheArtwork(for: currentPreset)
    }

    // Get recent presets (up to 5)
    let recentPresets = PresetManager.shared.getRecentPresets(limit: 5)
    await preCacheArtwork(for: recentPresets)

    print("📸 PresetArtworkManager: Cache warming complete")
  }

  /// Clean up orphaned artwork (not referenced by any preset)
  func cleanupOrphanedArtwork() async throws {
    guard let context = modelContext else {
      throw PresetArtworkError.noModelContext
    }

    print("📸 PresetArtworkManager: Starting orphaned artwork cleanup...")

    // Get all preset IDs and their artwork references
    let presets = PresetManager.shared.presets
    var referencedArtworkIds = Set<UUID>()

    for preset in presets {
      if let artworkId = preset.artworkId {
        referencedArtworkIds.insert(artworkId)
      }
      if let backgroundId = preset.backgroundImageId {
        referencedArtworkIds.insert(backgroundId)
      }
    }

    // Fetch all artwork
    let descriptor = FetchDescriptor<PresetArtwork>()
    let allArtwork = try context.fetch(descriptor)

    // Find and delete orphaned artwork
    var deletedCount = 0
    for artwork in allArtwork where !referencedArtworkIds.contains(artwork.id) {
      print("📸 PresetArtworkManager: Deleting orphaned artwork \(artwork.id)")
      context.delete(artwork)
      deletedCount += 1

      // Also remove from cache
      imageCache.removeValue(forKey: artwork.id)
    }

    if deletedCount > 0 {
      try context.save()
      print("📸 PresetArtworkManager: Deleted \(deletedCount) orphaned artwork items")
    } else {
      print("📸 PresetArtworkManager: No orphaned artwork found")
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
          print(
            "📸 PresetArtworkManager: Migrated \(migratedCount) artwork records to have imageType")
        }
      } catch {
        print("📸 PresetArtworkManager: Lazy migration failed: \(error)")
        hasMigrationRun = false  // Allow retry later
      }
    }
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
