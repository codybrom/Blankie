//
//  NowPlayingManager+Artwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//

import AVFoundation
import MediaPlayer
import SwiftUI
import os

#if os(iOS)
  import UIKit
#endif

extension NowPlayingManager {
  /// Load static artwork synchronously to avoid double-publishing that restarts animated artwork
  func loadStaticArtworkSync(from preset: Preset?, fallbackArtworkId: UUID?) async {
    // Priority order:
    // 1. Static artwork from artworkId (SwiftData) - TOP PRIORITY
    // 2. Bundled animated artwork square preview (from app bundle)
    // 3. Cached animated artwork square preview (from Documents)
    // 4. Other cached paths

    // PRIORITY 1: Static artwork from artworkId
    let targetArtworkId = preset?.artworkId ?? fallbackArtworkId
    if let artworkId = targetArtworkId, artworkId != currentArtworkId {
      currentArtworkId = artworkId
      currentStaticArtworkPath = nil
      await loadAndUpdateArtwork(artworkId: artworkId, shouldPublish: false)
      return
    }

    #if os(iOS) && !WIDGET_EXTENSION
      if let preset {
        // PRIORITY 2: For bundled animated artwork (ODR), load square preview from bundle
        if let bundledId = preset.animatedArtwork?.bundledIdentifier,
          let asset = BundledAnimatedLoop.allCases.first(where: { $0.id == bundledId }),
          let squarePreviewURL = Bundle.main.url(
            forResource: asset.squarePreviewResourceName,
            withExtension: asset.squarePreviewExtension
          ),
          let data = try? Data(contentsOf: squarePreviewURL)
        {
          Logger.nowPlaying.debug(
            "NowPlayingManager: Loading bundled square preview for \(bundledId)")
          currentStaticArtworkPath = nil
          currentArtworkId = nil
          updateArtwork(artworkData: data)
          return
        }

        // PRIORITY 3: Check for cached animated artwork square preview
        if let squarePreviewPath = preset.animatedArtwork?.squarePreviewPath,
          AnimatedArtworkFileStore.fileExists(at: squarePreviewPath),
          currentStaticArtworkPath != squarePreviewPath
        {
          Logger.nowPlaying.debug("NowPlayingManager: Loading cached square preview from Documents")
          currentStaticArtworkPath = squarePreviewPath
          currentArtworkId = nil
          let data = try? Data(
            contentsOf: AnimatedArtworkFileStore.absoluteURL(for: squarePreviewPath))
          updateArtwork(artworkData: data)
          return
        }

        // PRIORITY 4: Other cached paths (staticArtworkPath, previewPath)
        let candidatePath =
          preset.staticArtworkPath
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

    // No artwork found — always apply the Blankie fallback so presets without
    // artwork still show the NowPlaying.png icon on the lock screen / CarPlay.
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    updateArtwork(artworkData: nil)
  }

  /// Legacy async version - only use when not publishing immediately after
  func loadStaticArtwork(from preset: Preset?, fallbackArtworkId: UUID?) {
    staticArtworkTask?.cancel()

    // Priority order (same as loadStaticArtworkSync):
    // 1. Static artwork from artworkId (SwiftData) - TOP PRIORITY
    // 2. Bundled animated artwork square preview (from app bundle)
    // 3. Cached animated artwork square preview (from Documents)
    // 4. Other cached paths

    // PRIORITY 1: Static artwork from artworkId
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

    #if os(iOS) && !WIDGET_EXTENSION
      if let preset {
        // PRIORITY 2: Bundled animated artwork (ODR) square preview from bundle
        if let bundledId = preset.animatedArtwork?.bundledIdentifier,
          let asset = BundledAnimatedLoop.allCases.first(where: { $0.id == bundledId }),
          let squarePreviewURL = Bundle.main.url(
            forResource: asset.squarePreviewResourceName,
            withExtension: asset.squarePreviewExtension
          )
        {
          Logger.nowPlaying.debug(
            "NowPlayingManager: Loading bundled square preview for \(bundledId)")
          currentStaticArtworkPath = nil
          currentArtworkId = nil
          staticArtworkTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let data = try? Data(contentsOf: squarePreviewURL)
            await MainActor.run {
              self.updateArtwork(artworkData: data)

              // Update only the artwork key in MPNowPlayingInfoCenter to avoid restarting animated artwork
              if let artwork = self.nowPlayingInfo[MPMediaItemPropertyArtwork] {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
                  artwork
              }
            }
          }
          return
        }

        // PRIORITY 3: Cached animated artwork square preview
        if let squarePreviewPath = preset.animatedArtwork?.squarePreviewPath,
          AnimatedArtworkFileStore.fileExists(at: squarePreviewPath)
        {
          if currentStaticArtworkPath == squarePreviewPath {
            return
          }

          Logger.nowPlaying.debug("NowPlayingManager: Loading cached square preview from Documents")
          currentStaticArtworkPath = squarePreviewPath
          currentArtworkId = nil
          staticArtworkTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let data = try? Data(
              contentsOf: AnimatedArtworkFileStore.absoluteURL(for: squarePreviewPath))
            await MainActor.run {
              self.updateArtwork(artworkData: data)

              if let artwork = self.nowPlayingInfo[MPMediaItemPropertyArtwork] {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
                  artwork
              }
            }
          }
          return
        }
      }
    #endif

    // PRIORITY 4: Other cached paths
    #if os(iOS)
      if let preset {
        let candidatePath =
          preset.staticArtworkPath
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

              if let artwork = self.nowPlayingInfo[MPMediaItemPropertyArtwork] {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
                  artwork
              }
            }
          }
          return
        }
      }
    #endif

    // No artwork found — always apply the Blankie fallback so presets without
    // artwork still show the NowPlaying.png icon on the lock screen / CarPlay.
    currentStaticArtworkPath = nil
    currentArtworkId = nil
    updateArtwork(artworkData: nil)
  }

  func updateArtwork(artworkData: Data?) {
    Logger.nowPlaying.debug(
      "NowPlayingManager: Processing artwork data: \(artworkData != nil ? "\(artworkData!.count) bytes" : "None")"
    )
    if let customArtwork = loadCustomArtwork(from: artworkData) {
      Logger.nowPlaying.debug("NowPlayingManager: Custom artwork loaded successfully")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = customArtwork
    } else if let defaultArtwork = loadArtwork() {
      Logger.nowPlaying.debug("NowPlayingManager: Using default artwork")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = defaultArtwork
    } else {
      Logger.nowPlaying.debug("NowPlayingManager: No artwork available")
    }
  }

  /// Load artwork from SwiftData and update Now Playing info
  func loadAndUpdateArtwork(artworkId: UUID, shouldPublish: Bool = true) async {
    Logger.nowPlaying.debug(
      "NowPlayingManager: Loading artwork from SwiftData with ID: \(artworkId)")

    // Load artwork on background thread to prevent UI blocking
    let artworkData: Data? = await Task.detached {
      // Get the data directly from PresetArtworkManager instead of converting image
      let imageData = await PresetArtworkManager.shared.loadArtworkData(id: artworkId)
      if let imageData = imageData {
        Logger.nowPlaying.debug(
          "NowPlayingManager: Loaded artwork from SwiftData (\(imageData.count) bytes)")
      }
      return imageData
    }.value

    // Update artwork in memory on main thread
    await MainActor.run {
      if artworkData == nil {
        Logger.nowPlaying.debug("NowPlayingManager: No artwork found in SwiftData")
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
