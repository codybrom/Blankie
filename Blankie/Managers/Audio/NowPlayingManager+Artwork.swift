//
//  NowPlayingManager+Artwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//

import AVFoundation
import MediaPlayer
import SwiftUI
#if os(iOS)
  import UIKit
#endif

extension NowPlayingManager {
  /// Load static artwork synchronously to avoid double-publishing that restarts animated artwork
  func loadStaticArtworkSync(from preset: Preset?, fallbackArtworkId: UUID?) async {
    // Same logic as loadStaticArtwork but awaits artwork loading
    let targetArtworkId = preset?.artworkId ?? fallbackArtworkId
    if let artworkId = targetArtworkId, artworkId != currentArtworkId {
      currentArtworkId = artworkId
      currentStaticArtworkPath = nil
      await loadAndUpdateArtwork(artworkId: artworkId, shouldPublish: false)
      return
    }

    #if os(iOS)
      if let preset {
        let candidatePath = preset.staticArtworkPath
          ?? preset.animatedArtwork?.squarePreviewPath
          ?? preset.animatedArtwork?.previewPath

        if let candidatePath, AnimatedArtworkFileStore.fileExists(at: candidatePath),
           currentStaticArtworkPath != candidatePath
        {
          currentStaticArtworkPath = candidatePath
          currentArtworkId = nil
          let data = try? Data(contentsOf: AnimatedArtworkFileStore.absoluteURL(for: candidatePath))
          updateArtwork(artworkData: data)
          return
        }
      }
    #endif

    // No artwork or same as current
    if targetArtworkId == nil, currentArtworkId != nil || currentStaticArtworkPath != nil {
      currentArtworkId = nil
      currentStaticArtworkPath = nil
      updateArtwork(artworkData: nil)
    }
  }

  /// Legacy async version - only use when not publishing immediately after
  func loadStaticArtwork(from preset: Preset?, fallbackArtworkId: UUID?) {
    staticArtworkTask?.cancel()

    // Priority order for static artwork display (Control Center, CarPlay, etc):
    // 1. preset.artworkId (square static artwork from SwiftData)
    // 2. preset.staticArtworkPath (square static artwork from FileStore) - fallback for legacy presets
    // 3. preset.animatedArtwork?.squarePreviewPath (1:1 square preview from animated artwork)
    // 4. preset.animatedArtwork?.previewPath (3:4 portrait preview) - only if no square artwork exists
    // This ensures Control Center always shows square artwork when available

    // First, check if we have artworkId (preferred square static artwork)
    let targetArtworkId = preset?.artworkId ?? fallbackArtworkId
    if targetArtworkId != nil {
      let hadStaticArtworkPath = currentStaticArtworkPath != nil
      currentStaticArtworkPath = nil

      if targetArtworkId != currentArtworkId {
        currentArtworkId = targetArtworkId
        if let artworkId = targetArtworkId {
          Task {
            await loadAndUpdateArtwork(artworkId: artworkId)
          }
        } else {
          updateArtwork(artworkData: nil)
        }
      } else if targetArtworkId == nil, hadStaticArtworkPath {
        updateArtwork(artworkData: nil)
      }
      return
    }

    // No artworkId, try file-based static artwork paths
    #if os(iOS)
      if let preset {
        // Try square preview first (best for Control Center), then static path, then portrait preview
        let candidatePath = preset.staticArtworkPath
          ?? preset.animatedArtwork?.squarePreviewPath
          ?? preset.animatedArtwork?.previewPath

        if let candidatePath, AnimatedArtworkFileStore.fileExists(at: candidatePath) {
          if currentStaticArtworkPath == candidatePath {
            return
          }

          currentStaticArtworkPath = candidatePath
          currentArtworkId = nil
          let path = candidatePath
          staticArtworkTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let data = try? Data(contentsOf: AnimatedArtworkFileStore.absoluteURL(for: path))
            await MainActor.run {
              self.updateArtwork(artworkData: data)

              // Update only the artwork key in MPNowPlayingInfoCenter to avoid restarting animated artwork
              if let artwork = self.nowPlayingInfo[MPMediaItemPropertyArtwork] {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
              }
            }
          }
          return
        }
      }
    #endif

    // No artwork at all - clear everything
    let hadStaticArtworkPath = currentStaticArtworkPath != nil
    currentStaticArtworkPath = nil
    currentArtworkId = nil

    if hadStaticArtworkPath {
      updateArtwork(artworkData: nil)
    }
  }

  func updateArtwork(artworkData: Data?) {
    print(
      "🎨 NowPlayingManager: Processing artwork data: \(artworkData != nil ? "✅ \(artworkData!.count) bytes" : "❌ None")"
    )
    if let customArtwork = loadCustomArtwork(from: artworkData) {
      print("🎨 NowPlayingManager: ✅ Custom artwork loaded successfully")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = customArtwork
    } else if let defaultArtwork = loadArtwork() {
      print("🎨 NowPlayingManager: Using default artwork")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = defaultArtwork
    } else {
      print("🎨 NowPlayingManager: ❌ No artwork available")
    }
  }

  /// Load artwork from SwiftData and update Now Playing info
  func loadAndUpdateArtwork(artworkId: UUID, shouldPublish: Bool = true) async {
    print("🎨 NowPlayingManager: Loading artwork from SwiftData with ID: \(artworkId)")

    // Load artwork on background thread to prevent UI blocking
    let artworkData: Data? = await Task.detached {
      // Get the data directly from PresetArtworkManager instead of converting image
      let imageData = await PresetArtworkManager.shared.loadArtworkData(id: artworkId)
      if let imageData = imageData {
        print(
          "🎨 NowPlayingManager: ✅ Loaded artwork from SwiftData (\(imageData.count) bytes)"
        )
      }
      return imageData
    }.value

    // Update artwork in memory on main thread
    await MainActor.run {
      if artworkData == nil {
        print("🎨 NowPlayingManager: ⚠️ No artwork found in SwiftData")
      }
      updateArtwork(artworkData: artworkData)

      // Only publish if requested (when called from old async flow)
      // When called from performNowPlayingUpdate, we skip publishing to avoid restarting animated artwork
      if shouldPublish {
        // Update only the artwork key in MPNowPlayingInfoCenter to avoid restarting animated artwork
        // This preserves the animated artwork objects while updating the static artwork
        if let artwork = nowPlayingInfo[MPMediaItemPropertyArtwork] {
          MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
      }
    }
  }
}
