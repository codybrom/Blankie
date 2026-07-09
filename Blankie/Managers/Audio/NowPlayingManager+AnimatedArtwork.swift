//
//  NowPlayingManager+AnimatedArtwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//

import os

#if os(iOS)
  import AVFoundation
  import MediaPlayer
  import UIKit

  extension NowPlayingManager {
    @objc func animatedArtworkConditionChanged() {
      republishCurrentPreset()
    }

    func updateAnimatedArtwork(for preset: Preset?) {
      guard let preset else {
        removeAnimatedArtwork()
        return
      }

      guard shouldPublishAnimatedArtwork() else {
        removeAnimatedArtwork()
        return
      }

      guard let artworkKey = determineAnimatedArtworkKey() else {
        removeAnimatedArtwork()
        return
      }

      // Check if we should skip because artwork hasn't changed
      guard !shouldSkipAnimatedArtworkUpdate(for: preset) else {
        return
      }

      // Try to load resources (may trigger a Background Assets download). The
      // key decides which variant to serve: iPad's lock screen advertises only
      // the 1x1 key, so it needs the square crop, not the 3:4 portrait master.
      guard let resources = loadAnimatedArtworkResources(for: preset, key: artworkKey) else {
        // Resources not available yet (downloading) - keep existing artwork, don't remove
        // When download completes, updateAnimatedArtwork will be called again
        return
      }

      publishAnimatedArtwork(preset: preset, resources: resources, artworkKey: artworkKey)
    }

    private func shouldPublishAnimatedArtwork() -> Bool {
      GlobalSettings.shared.lockScreenBackgroundEnabled
        && !UIAccessibility.isReduceMotionEnabled
        && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func loadAnimatedArtworkResources(for preset: Preset, key: AnimatedArtworkKey) -> (
      loopURL: URL, previewImage: UIImage
    )? {
      guard let resources = animatedArtworkResources(for: preset, key: key),
        let previewImage = resources.previewImage
      else {
        return nil
      }
      return (loopURL: resources.loopURL, previewImage: previewImage)
    }

    private func determineAnimatedArtworkKey() -> AnimatedArtworkKey? {
      let supportedKeys = Set(MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys)
      if supportedKeys.contains(AnimatedArtworkKey.square.rawValue) {
        return .square
      } else if supportedKeys.contains(AnimatedArtworkKey.portrait.rawValue) {
        return .portrait
      }
      return nil
    }

    private func shouldSkipAnimatedArtworkUpdate(for preset: Preset) -> Bool {
      // Bundled artwork has no Documents loopPath (its video is served from the
      // Background Assets pack), so key change-detection off the bundled id.
      let loopKey = preset.animatedArtwork?.loopPath ?? preset.animatedArtwork?.bundledIdentifier
      let previewPath = preset.animatedArtwork?.previewPath ?? preset.staticArtworkPath
      return currentAnimatedLoopPath == loopKey && currentAnimatedPreviewPath == previewPath
    }

    private func publishAnimatedArtwork(
      preset: Preset,
      resources: (loopURL: URL, previewImage: UIImage),
      artworkKey: AnimatedArtworkKey
    ) {
      let loopKey = preset.animatedArtwork?.loopPath ?? preset.animatedArtwork?.bundledIdentifier
      let previewPath = preset.animatedArtwork?.previewPath ?? preset.staticArtworkPath

      let artworkID = loopKey ?? preset.id.uuidString
      nowPlayingInfo[artworkKey.rawValue] = Self.makeAnimatedArtwork(
        artworkID: artworkID,
        previewImage: resources.previewImage,
        loopURL: resources.loopURL
      )
      currentAnimatedLoopPath = loopKey
      currentAnimatedPreviewPath = previewPath
    }

    /// Wraps the preview image and loop URL in `MPMediaItemAnimatedArtwork`.
    /// Declared `nonisolated` so the request handler closures do NOT inherit
    /// `NowPlayingManager`'s `@MainActor` isolation — MediaRemote invokes them
    /// from its own `NowPlayingInfo` serial queue, and an isolated closure traps
    /// the runtime's executor check there (mirrors `makeArtwork`).
    nonisolated static func makeAnimatedArtwork(
      artworkID: String,
      previewImage: UIImage,
      loopURL: URL
    ) -> MPMediaItemAnimatedArtwork {
      MPMediaItemAnimatedArtwork(
        artworkID: artworkID,
        previewImageRequestHandler: { _, completion in
          completion(previewImage)
        },
        videoAssetFileURLRequestHandler: { _, completion in
          completion(loopURL)
        }
      )
    }

    func removeAnimatedArtwork() {
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.square.rawValue)
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.portrait.rawValue)
      currentAnimatedLoopPath = nil
      currentAnimatedPreviewPath = nil
    }

    func animatedArtworkResources(for preset: Preset, key: AnimatedArtworkKey) -> (
      loopURL: URL, previewImage: UIImage?
    )? {
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
        return loadBundledBackgroundResources(bundledId: bundledId, key: key, preset: preset)
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
      preset: Preset
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
              self.updateAnimatedArtwork(for: preset)
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
