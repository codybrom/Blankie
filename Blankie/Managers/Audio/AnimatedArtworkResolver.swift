//
//  AnimatedArtworkResolver.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  Where a preset's animated artwork actually lives: the Documents cache, or a
//  Background Assets pack that may still need downloading.

#if os(iOS)
  import Foundation
  import UIKit
  import os

  /// Resolves a preset's loop video and preview image, downloading the bundled
  /// artwork's asset pack when it isn't on the device yet.
  @MainActor
  final class AnimatedArtworkResolver {
    // In-flight pack downloads keyed by pack id, so duplicate triggers for the
    // same artwork share one download.
    private var animatedArtworkDownloadTasks: [String: Task<Void, Never>] = [:]

    /// The loop video and preview for `key`, or nil when nothing is playable
    /// yet. A bundled pack that still has to download returns nil now and calls
    /// `onDownloaded` once it lands.
    /// - Parameter downloadIfMissing: false returns nil for a pack that isn't on
    ///   the device, without starting a download.
    func resources(
      for preset: Preset,
      key: AnimatedArtworkKey,
      downloadIfMissing: Bool = true,
      onDownloaded: @escaping @MainActor () -> Void
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      Logger.nowPlaying.debug("animatedArtworkResources called. preset id: \(preset.id.uuidString)")
      guard let animatedArtwork = preset.animatedArtwork else {
        Logger.nowPlaying.debug("animatedArtwork is nil, returning nil")
        return nil
      }

      // The Documents cache wins over the asset pack, so cached artwork plays on
      // the lock screen without a foreground download.
      if let loopPath = animatedArtwork.loopPath {
        let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
        if FileManager.default.fileExists(atPath: loopURL.path) {
          Logger.nowPlaying.debug("Found cached video in Documents: \(loopPath)")
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
          bundledId: bundledId, key: key, downloadIfMissing: downloadIfMissing,
          onDownloaded: onDownloaded)
      }

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
      downloadIfMissing: Bool,
      onDownloaded: @escaping @MainActor () -> Void
    ) -> (loopURL: URL, previewImage: UIImage?)? {
      // Each clip ships as a 3:4 portrait pack "<id>" for iPhone and a 1:1 square
      // pack "<id>Square" for iPad (which advertises only the 1x1 key).
      let packId = key == .square ? "\(bundledId)Square" : bundledId
      let previewResource = key == .square ? "\(bundledId)Square" : bundledId

      guard let loopURL = BackgroundResourceManager.shared.availableURL(for: packId) else {
        // A non-preferred variant is served only if already local. Each device
        // fetches one pack per clip.
        guard downloadIfMissing else { return nil }

        Logger.nowPlaying.debug(
          "Artwork pack \(packId) not available, triggering background download")

        if animatedArtworkDownloadTasks[packId] == nil {
          animatedArtworkDownloadTasks[packId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.animatedArtworkDownloadTasks.removeValue(forKey: packId) }
            do {
              _ = try await BackgroundResourceManager.shared.resourceURL(for: packId)
              Logger.nowPlaying.debug("Downloaded artwork pack: \(packId)")
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
