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

      // Try to load resources (may trigger ODR download in background)
      guard let resources = loadAnimatedArtworkResources(for: preset) else {
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

    private func loadAnimatedArtworkResources(for preset: Preset) -> (
      loopURL: URL, previewImage: UIImage
    )? {
      guard let resources = animatedArtworkResources(for: preset),
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
      let animatedArtwork = MPMediaItemAnimatedArtwork(
        artworkID: artworkID,
        previewImageRequestHandler: { _, completion in
          completion(resources.previewImage)
        },
        videoAssetFileURLRequestHandler: { _, completion in
          completion(resources.loopURL)
        }
      )

      nowPlayingInfo[artworkKey.rawValue] = animatedArtwork
      currentAnimatedLoopPath = loopKey
      currentAnimatedPreviewPath = previewPath
    }

    func removeAnimatedArtwork() {
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.square.rawValue)
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.portrait.rawValue)
      currentAnimatedLoopPath = nil
      currentAnimatedPreviewPath = nil
    }

    func animatedArtworkResources(for preset: Preset) -> (loopURL: URL, previewImage: UIImage?)? {
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
        return loadBundledBackgroundResources(bundledId: bundledId, preset: preset)
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
      preset: Preset
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      // The video lives in its Background Assets pack; serve it directly.
      guard let loopURL = BackgroundResourceManager.shared.availableURL(for: bundledId) else {
        Logger.nowPlaying.debug(
          "Artwork pack \(bundledId) not available, triggering background download")

        // Coalesce duplicate triggers for the same id (scrolling back onto a
        // card that's already downloading, repeated preset re-publishes, etc.)
        if animatedArtworkDownloadTasks[bundledId] == nil {
          animatedArtworkDownloadTasks[bundledId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.animatedArtworkDownloadTasks.removeValue(forKey: bundledId) }
            do {
              _ = try await BackgroundResourceManager.shared.resourceURL(for: bundledId)
              Logger.nowPlaying.debug("Downloaded artwork pack: \(bundledId)")
              // Re-publish now that the pack is available locally.
              self.updateAnimatedArtwork(for: preset)
            } catch {
              Logger.nowPlaying.error(
                "Failed to download artwork pack \(bundledId, privacy: .public): \(error, privacy: .public)"
              )
            }
          }
        }

        return nil
      }

      Logger.nowPlaying.debug("Artwork pack \(bundledId) available at: \(loopURL)")

      // Preview image is bundled (named after the bundled id, e.g. "OceanWaves.jpg").
      var previewImage: UIImage?
      if let previewURL = Bundle.main.url(forResource: bundledId, withExtension: "jpg") {
        previewImage = UIImage(contentsOfFile: previewURL.path)
      } else {
        Logger.nowPlaying.debug("Preview image not found in bundle: \(bundledId).jpg")
      }

      return (loopURL: loopURL, previewImage: previewImage)
    }
  }
#endif
