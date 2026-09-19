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

      guard NowPlayingDisplay.shouldPublishAnimatedArtwork() else {
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

    private func loadAnimatedArtworkResources(for preset: Preset, key: AnimatedArtworkKey) -> (
      loopURL: URL, previewImage: UIImage
    )? {
      guard
        let resources = animatedArtworkResolver.resources(
          for: preset, key: key,
          onDownloaded: { [weak self] in self?.updateAnimatedArtwork(for: preset) }),
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
  }
#endif
