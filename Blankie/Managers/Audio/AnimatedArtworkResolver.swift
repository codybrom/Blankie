//
//  AnimatedArtworkResolver.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  Where a preset's animated artwork actually lives — Documents cache, or a
//  Background Assets pack that may still need downloading — shared by both
//  Now Playing backends.

import os

#if os(iOS)
  import Foundation
  import UIKit

  /// Resolves a preset's loop video and preview image, downloading the bundled
  /// artwork's asset pack when it isn't on the device yet.
  @MainActor
  final class AnimatedArtworkResolver {
    // ODR download + Documents-cache tasks in flight, keyed by bundled id.
    // Lets duplicate triggers for the same animated artwork coalesce instead
    // of spawning parallel downloads and cache-copy attempts.
    private var animatedArtworkDownloadTasks: [String: Task<Void, Never>] = [:]

    /// The loop video and preview for `key`, or nil when nothing is playable
    /// yet. A bundled pack that still has to download returns nil now and calls
    /// `onDownloaded` once it lands.
    func resources(
      for preset: Preset,
      key: AnimatedArtworkKey,
      onDownloaded: @escaping @MainActor () -> Void
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      Logger.nowPlaying.debug("animatedArtworkResources called. preset id: \(preset.id.uuidString)")
      guard let animatedArtwork = preset.animatedArtwork else {
        Logger.nowPlaying.debug("animatedArtwork is nil, returning nil")
        return nil
      }

      // CRITICAL: Always check Documents directory FIRST before trying ODR
      // When bundled resources are selected, they're copied to Documents for permanent caching
      // This ensures animated artwork works on lock screen without requiring foreground downloads
      if let loopPath = animatedArtwork.loopPath {
        let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
        if FileManager.default.fileExists(atPath: loopURL.path) {
          Logger.nowPlaying.debug("Found cached video in Documents: \(loopPath)")
          // Load preview image from Documents if available
          var previewImage: UIImage?
          if let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath {
            let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
            if FileManager.default.fileExists(atPath: previewURL.path) {
              previewImage = UIImage(contentsOfFile: previewURL.path)
              Logger.nowPlaying.debug("Loaded cached preview image from Documents")
            }
          }
          return (loopURL: loopURL, previewImage: previewImage)
        }
      }

      // Bundled artwork: the video is served straight from its Background
      // Assets pack (no Documents copy), with the preview image from the bundle.
      if animatedArtwork.source == .bundled, let bundledId = animatedArtwork.bundledIdentifier {
        Logger.nowPlaying.debug("Bundled artwork, resolving Background Assets pack: \(bundledId)")
        return loadBundledBackgroundResources(
          bundledId: bundledId, key: key, onDownloaded: onDownloaded)
      }

      // No loopPath and no bundled ID - invalid state
      guard let loopPath = animatedArtwork.loopPath else {
        Logger.nowPlaying.debug("loopPath is nil, returning nil")
        return nil
      }

      let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath
      Logger.nowPlaying.debug(
        "Custom artwork - loopPath: \(String(describing: loopPath)), previewPath: \(String(describing: previewPath))"
      )

      let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
      guard FileManager.default.fileExists(atPath: loopURL.path) else {
        Logger.nowPlaying.debug("File does not exist at loopURL: \(loopURL)")
        return nil
      }

      var previewImage: UIImage?
      if let previewPath = previewPath {
        let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
        guard FileManager.default.fileExists(atPath: previewURL.path) else {
          Logger.nowPlaying.debug("File does not exist at previewURL: \(previewURL)")
          return nil
        }
        previewImage = UIImage(contentsOfFile: previewURL.path)
        if previewImage == nil {
          Logger.nowPlaying.error(
            "Failed to load preview image from: \(previewURL.lastPathComponent)")
        }
      }

      Logger.nowPlaying.debug(
        "Succeeded in building animatedArtworkResources with loopURL: \(loopURL), previewImage: \(previewImage != nil)"
      )

      return (loopURL: loopURL, previewImage: previewImage)
    }

    private func loadBundledBackgroundResources(
      bundledId: String,
      key: AnimatedArtworkKey,
      onDownloaded: @escaping @MainActor () -> Void
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      // Each clip ships as two variants so it animates on every lock screen:
      // the 3:4 portrait master (pack "<id>", preview "<id>.jpg") for iPhone,
      // and a 1:1 square crop (pack "<id>Square", preview "<id>Square.jpg") for
      // iPad, which advertises only the 1x1 key. The pack id and preview image
      // are otherwise resolved identically.
      let packId = key == .square ? "\(bundledId)Square" : bundledId
      let previewResource = key == .square ? "\(bundledId)Square" : bundledId

      // The video lives in its Background Assets pack; serve it directly.
      guard let loopURL = BackgroundResourceManager.shared.availableURL(for: packId) else {
        Logger.nowPlaying.debug(
          "Artwork pack \(packId) not available, triggering background download")

        // Coalesce duplicate triggers for the same pack (scrolling back onto a
        // card that's already downloading, repeated preset re-publishes, etc.)
        if animatedArtworkDownloadTasks[packId] == nil {
          animatedArtworkDownloadTasks[packId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.animatedArtworkDownloadTasks.removeValue(forKey: packId) }
            do {
              _ = try await BackgroundResourceManager.shared.resourceURL(for: packId)
              Logger.nowPlaying.debug("Downloaded artwork pack: \(packId)")
              // Re-publish now that the pack is available locally.
              onDownloaded()
            } catch {
              Logger.nowPlaying.error(
                "Failed to download artwork pack \(packId, privacy: .public): \(error, privacy: .public)"
              )
            }
          }
        }

        return nil
      }

      Logger.nowPlaying.debug("Artwork pack \(packId) available at: \(loopURL)")

      // Preview image is bundled (named after the variant, e.g. "OceanWaves.jpg"
      // or "OceanWavesSquare.jpg").
      var previewImage: UIImage?
      if let previewURL = Bundle.main.url(forResource: previewResource, withExtension: "jpg") {
        previewImage = UIImage(contentsOfFile: previewURL.path)
      } else {
        Logger.nowPlaying.debug("Preview image not found in bundle: \(previewResource).jpg")
      }

      return (loopURL: loopURL, previewImage: previewImage)
    }
  }
#endif
