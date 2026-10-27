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

    /// A pack finished downloading. Rebuild for whatever preset is current now
    /// and publish in full, since incremental updates never carry artwork keys.
    func animatedArtworkDidDownload() {
      needsArtworkRebuild = true
      republishCurrentPreset()
    }

    func updateAnimatedArtwork(for preset: Preset?) {
      // No animation at all (not even the inherited default) clears the card.
      // Only a still-downloading pack keeps the current loop below.
      guard let preset, preset.animatedArtwork != nil else {
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

      guard !shouldSkipAnimatedArtworkUpdate(for: preset) else {
        return
      }

      // May start a Background Assets download. The key picks the variant: iPad's
      // lock screen advertises only the 1x1 key, so it gets the square crop.
      guard let resources = loadAnimatedArtworkResources(for: preset, key: artworkKey) else {
        // Still downloading: keep the current artwork; the download callback republishes.
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
          onDownloaded: { [weak self] in self?.animatedArtworkDidDownload() }),
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
    /// `nonisolated` so the handlers don't inherit `@MainActor`: MediaRemote calls
    /// them on its own serial queue, where an isolated closure traps (as `makeArtwork`).
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
