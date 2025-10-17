//
//  NowPlayingManager+AnimatedArtwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//

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

      guard shouldPublishAnimatedArtwork(),
            let resources = loadAnimatedArtworkResources(for: preset)
      else {
        removeAnimatedArtwork()
        return
      }

      guard #available(iOS 26.0, *),
            let artworkKey = determineAnimatedArtworkKey()
      else {
        removeAnimatedArtwork()
        return
      }

      guard !shouldSkipAnimatedArtworkUpdate(for: preset) else {
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

    @available(iOS 26.0, *)
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
      let loopPath = preset.animatedArtwork?.loopPath
      let previewPath = preset.animatedArtwork?.previewPath ?? preset.staticArtworkPath
      return currentAnimatedLoopPath == loopPath && currentAnimatedPreviewPath == previewPath
    }

    @available(iOS 26.0, *)
    private func publishAnimatedArtwork(
      preset: Preset,
      resources: (loopURL: URL, previewImage: UIImage),
      artworkKey: AnimatedArtworkKey
    ) {
      let loopPath = preset.animatedArtwork?.loopPath
      let previewPath = preset.animatedArtwork?.previewPath ?? preset.staticArtworkPath

      let artworkID = loopPath ?? preset.id.uuidString
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
      currentAnimatedLoopPath = loopPath
      currentAnimatedPreviewPath = previewPath
    }

    func removeAnimatedArtwork() {
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.square.rawValue)
      nowPlayingInfo.removeValue(forKey: AnimatedArtworkKey.portrait.rawValue)
      currentAnimatedLoopPath = nil
      currentAnimatedPreviewPath = nil
    }

    func animatedArtworkResources(for preset: Preset) -> (loopURL: URL, previewImage: UIImage?)? {
      print("[DEBUG] animatedArtworkResources called. preset id: \(preset.id.uuidString)")
      guard let animatedArtwork = preset.animatedArtwork else {
        print("[DEBUG] animatedArtwork is nil, returning nil")
        return nil
      }

      guard let loopPath = animatedArtwork.loopPath else {
        print("[DEBUG] loopPath is nil, returning nil")
        return nil
      }

      let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath
      print(
        "[DEBUG] loopPath: \(String(describing: loopPath)), previewPath: \(String(describing: previewPath))"
      )

      let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
      guard FileManager.default.fileExists(atPath: loopURL.path) else {
        print("[DEBUG] File does not exist at loopURL: \(loopURL)")
        return nil
      }

      var previewImage: UIImage?
      if let previewPath = previewPath {
        let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
        guard FileManager.default.fileExists(atPath: previewURL.path) else {
          print("[DEBUG] File does not exist at previewURL: \(previewURL)")
          return nil
        }
        previewImage = UIImage(contentsOfFile: previewURL.path)
        if previewImage == nil {
          print("[DEBUG] Failed to load preview image from: \(previewURL)")
        }
      }

      print(
        "[DEBUG] Succeeded in building animatedArtworkResources with loopURL: \(loopURL), previewImage: \(previewImage != nil)"
      )

      return (loopURL: loopURL, previewImage: previewImage)
    }
  }
#endif
