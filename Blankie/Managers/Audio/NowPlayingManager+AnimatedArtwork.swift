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

      guard shouldPublishAnimatedArtwork() else {
        removeAnimatedArtwork()
        return
      }

      guard #available(iOS 26.0, *),
            let artworkKey = determineAnimatedArtworkKey()
      else {
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

      // CRITICAL: Always check Documents directory FIRST before trying ODR
      // When bundled resources are selected, they're copied to Documents for permanent caching
      // This ensures animated artwork works on lock screen without requiring foreground downloads
      if let loopPath = animatedArtwork.loopPath {
        let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
        if FileManager.default.fileExists(atPath: loopURL.path) {
          print("[DEBUG] Found cached video in Documents: \(loopPath)")
          // Load preview image from Documents if available
          var previewImage: UIImage?
          if let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath {
            let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
            if FileManager.default.fileExists(atPath: previewURL.path) {
              previewImage = UIImage(contentsOfFile: previewURL.path)
              print("[DEBUG] Loaded cached preview image from Documents")
            }
          }
          return (loopURL: loopURL, previewImage: previewImage)
        }
      }

      // If not in Documents cache, try loading from ODR (requires foreground)
      if animatedArtwork.source == .bundled, let bundledId = animatedArtwork.bundledIdentifier {
        print("[DEBUG] Not cached in Documents, trying ODR resource: \(bundledId)")
        return loadBundledODRResources(bundledId: bundledId, animatedArtwork: animatedArtwork, preset: preset)
      }

      // No loopPath and no bundled ID - invalid state
      guard let loopPath = animatedArtwork.loopPath else {
        print("[DEBUG] loopPath is nil, returning nil")
        return nil
      }

      let previewPath = animatedArtwork.previewPath ?? preset.staticArtworkPath
      print(
        "[DEBUG] Custom artwork - loopPath: \(String(describing: loopPath)), previewPath: \(String(describing: previewPath))"
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

    private func loadBundledODRResources(
      bundledId: String,
      animatedArtwork: AnimatedArtworkRef,
      preset: Preset
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      // Check if ODR resource is available
      guard OnDemandResourceManager.shared.isResourceAvailable(bundledId),
            let loopURL = Bundle.main.url(forResource: bundledId, withExtension: "mov")
      else {
        print("[DEBUG] ODR resource \(bundledId) not available, triggering download and cache")

        // Trigger download asynchronously and copy to Documents for permanent caching
        Task { @MainActor in
          do {
            let videoURL = try await OnDemandResourceManager.shared.requestVideoResource(bundledId)
            print("[DEBUG] Successfully downloaded ODR resource: \(bundledId)")

            // Copy to Documents for permanent caching (prevents future re-downloads)
            await self.cacheODRResourceToDocuments(
              bundledId: bundledId,
              videoURL: videoURL,
              animatedArtwork: animatedArtwork,
              preset: preset
            )

            // Trigger a single refresh after successful download and caching
            self.updateAnimatedArtwork(for: preset)
          } catch {
            print("[DEBUG] Failed to download ODR resource \(bundledId): \(error)")
          }
        }

        return nil
      }

      print("[DEBUG] ODR resource \(bundledId) is available at: \(loopURL)")

      // Copy to Documents for permanent caching if not already done
      // This handles the case where ODR resource is available but not yet permanently cached
      Task { @MainActor in
        await self.cacheODRResourceToDocuments(
          bundledId: bundledId,
          videoURL: loopURL,
          animatedArtwork: animatedArtwork,
          preset: preset
        )
      }

      // Load preview image - for bundled resources, use bundledId + ".jpg" pattern
      var previewImage: UIImage?

      // For bundled ODR resources, the preview image should be named the same as the bundled ID
      // (e.g., "OceanWaves.jpg" for bundledId "OceanWaves")
      let previewName = bundledId
      if let previewURL = Bundle.main.url(forResource: previewName, withExtension: "jpg") {
        previewImage = UIImage(contentsOfFile: previewURL.path)
        print("[DEBUG] Loaded preview image from bundle: \(previewURL)")
      } else {
        print("[DEBUG] Preview image not found in bundle: \(previewName).jpg")
      }

      return (loopURL: loopURL, previewImage: previewImage)
    }

    /// Copy ODR resource to Documents for permanent caching
    private func cacheODRResourceToDocuments(
      bundledId: String,
      videoURL: URL,
      animatedArtwork: AnimatedArtworkRef,
      preset: Preset
    ) async {
      var preset = preset // Create mutable copy

      // Skip if already cached to Documents
      if let loopPath = animatedArtwork.loopPath,
         AnimatedArtworkFileStore.fileExists(at: loopPath)
      {
        print("[DEBUG] ODR resource \(bundledId) already cached to Documents at: \(loopPath)")
        return
      }

      do {
        // Find the bundled asset info
        guard let asset = BundledAnimatedLoop.allCases.first(where: { $0.id == bundledId }) else {
          print("[DEBUG] BundledAnimatedLoop not found for \(bundledId)")
          return
        }

        // Load preview images from bundle
        guard let previewURL = Bundle.main.url(
          forResource: asset.previewResourceName,
          withExtension: asset.previewExtension
        ) else {
          print("[DEBUG] Preview image not found for \(bundledId)")
          return
        }

        guard let squarePreviewURL = Bundle.main.url(
          forResource: asset.squarePreviewResourceName,
          withExtension: asset.squarePreviewExtension
        ) else {
          print("[DEBUG] Square preview image not found for \(bundledId)")
          return
        }

        // Generate new paths for Documents cache
        let assetId = UUID()
        let loopRel = AnimatedArtworkFileStore.makeRelativeLoopPath(
          for: assetId,
          fileExtension: videoURL.pathExtension
        )
        let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId,
          fileExtension: previewURL.pathExtension
        )
        let squarePreviewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId,
          fileExtension: squarePreviewURL.pathExtension,
          suffix: "Square"
        )

        // Copy files to Documents
        _ = try AnimatedArtworkFileStore.copyItem(at: videoURL, to: loopRel)
        _ = try AnimatedArtworkFileStore.copyItem(at: previewURL, to: previewRel)
        _ = try AnimatedArtworkFileStore.copyItem(at: squarePreviewURL, to: squarePreviewRel)

        print("[DEBUG] Successfully cached ODR resource \(bundledId) to Documents: \(loopRel)")

        // Update preset with new paths
        await MainActor.run {
          preset.animatedArtwork = AnimatedArtworkRef(
            source: .bundled,
            loopPath: loopRel,
            previewPath: previewRel,
            squarePreviewPath: squarePreviewRel,
            preferredAspect: animatedArtwork.preferredAspect,
            bundledIdentifier: bundledId
          )

          // Update preset in PresetManager
          if let index = PresetManager.shared.presets.firstIndex(where: { $0.id == preset.id }) {
            PresetManager.shared.updatePresetAtIndex(index, with: preset)
          }

          // Save preset changes
          PresetManager.shared.savePresets()
        }
      } catch {
        print("[DEBUG] Failed to cache ODR resource \(bundledId) to Documents: \(error)")
      }
    }
  }
#endif
