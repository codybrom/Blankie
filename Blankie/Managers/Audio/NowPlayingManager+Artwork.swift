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
  /// Loads static artwork synchronously so the caller publishes once (a second
  /// publish restarts animated artwork).
  func loadStaticArtworkSync(from preset: Preset?, fallbackArtworkId: UUID?) async {
    // Priority: stored artwork (artworkId), bundled square preview, cached square
    // preview, then other cached paths.
    let targetArtworkId = preset?.artworkId ?? fallbackArtworkId
    if let artworkId = targetArtworkId {
      // Already showing (a forced refresh of the same preset): keep it.
      guard artworkId != currentArtworkId else { return }
      currentStaticArtworkPath = nil
      // Read synchronously (as the OS 27 backend does) so a second update can't
      // interleave and pair one preset's title with another's artwork.
      let data = PresetArtworkManager.shared.storedArtworkData(id: artworkId)
      // Record the id only once it loads, so a failed read is retried later.
      currentArtworkId = data == nil ? nil : artworkId
      updateArtwork(artworkData: data)
      return
    }

    #if os(iOS) && !WIDGET_EXTENSION
      if let preset {
        // Bundled animated artwork (ODR): square preview from the app bundle.
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

        // Cached animated artwork square preview.
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

        // Other cached paths.
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

    // No artwork: show the Blankie fallback on the lock screen and CarPlay.
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    updateArtwork(artworkData: nil)
  }

  /// Async variant for callers that don't publish right after. Writes only the
  /// artwork key itself.
  func loadStaticArtwork(from preset: Preset?, fallbackArtworkId: UUID?) {
    staticArtworkTask?.cancel()

    // Same priority order as loadStaticArtworkSync.
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
        // Bundled animated artwork (ODR): square preview from the app bundle.
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

              // Write only the artwork key so animated artwork doesn't restart.
              if let artwork = self.nowPlayingInfo[MPMediaItemPropertyArtwork] {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
                  artwork
              }
            }
          }
          return
        }

        // Cached animated artwork square preview.
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

    // Other cached paths.
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

    // No artwork: show the Blankie fallback on the lock screen and CarPlay.
    currentStaticArtworkPath = nil
    currentArtworkId = nil
    updateArtwork(artworkData: nil)
  }

  func updateArtwork(artworkData: Data?) {
    Logger.nowPlaying.debug(
      "NowPlayingManager: Processing artwork data: \(artworkData != nil ? "\(artworkData!.count) bytes" : "None")"
    )
    let fallbackGlyph = NowPlayingDisplay.mixFallbackGlyph()
    shownFallbackGlyph = nil
    if let customArtwork = loadCustomArtwork(from: artworkData) {
      Logger.nowPlaying.debug("NowPlayingManager: Custom artwork loaded successfully")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = customArtwork
    } else if let defaultArtwork = loadArtwork(glyph: fallbackGlyph) {
      Logger.nowPlaying.debug("NowPlayingManager: Using default artwork")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = defaultArtwork
      shownFallbackGlyph = fallbackGlyph
    } else {
      Logger.nowPlaying.debug("NowPlayingManager: No artwork available")
    }
  }

  /// Redraws the fallback when the glyph it shows is out of date. A new preset
  /// selects its sounds a beat after its first publish, so the fallback drawn
  /// then pictures the previous selection. Returns whether it redrew.
  func redrawFallbackIfStale() -> Bool {
    guard let shown = shownFallbackGlyph, shown != NowPlayingDisplay.mixFallbackGlyph() else {
      return false
    }
    updateArtwork(artworkData: nil)
    return true
  }

  /// Loads stored artwork off the main thread and applies it.
  func loadAndUpdateArtwork(artworkId: UUID, shouldPublish: Bool = true) async {
    Logger.nowPlaying.debug(
      "NowPlayingManager: Loading artwork from SwiftData with ID: \(artworkId)")

    let artworkData: Data? = await Task.detached {
      let imageData = await PresetArtworkManager.shared.loadArtworkData(id: artworkId)
      if let imageData = imageData {
        Logger.nowPlaying.debug(
          "NowPlayingManager: Loaded artwork from SwiftData (\(imageData.count) bytes)")
      }
      return imageData
    }.value

    await MainActor.run {
      if artworkData == nil {
        Logger.nowPlaying.debug("NowPlayingManager: No artwork found in SwiftData")
      }
      updateArtwork(artworkData: artworkData)

      if shouldPublish {
        // Write only the artwork key so animated artwork doesn't restart.
        if let artwork = nowPlayingInfo[MPMediaItemPropertyArtwork] {
          MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
      }
    }
  }
}
