//
//  BlankieAnimatedArtwork.swift
//  Blankie
//
//  Created by Cody Bromley on 7/3/25.
//

import Foundation

#if os(iOS)
  import AVFoundation
  import MediaPlayer
  import UIKit

  #if canImport(NowPlaying)
    import NowPlaying
  #endif

  enum AnimatedArtworkKey: String {
    case square = "MPNowPlayingInfoProperty1x1AnimatedArtwork"
    case portrait = "MPNowPlayingInfoProperty3x4AnimatedArtwork"

    /// The variant this device's lock screen shows (iPad advertises only 1x1,
    /// iPhone 3x4), so previews match it and each device fetches one pack. On
    /// iOS 27 the NowPlaying framework answers, since it must not be mixed with
    /// MediaPlayer; a device that accepts both crops picks one by idiom.
    nonisolated static var preferredForDevice: AnimatedArtworkKey {
      #if canImport(NowPlaying)
        if #available(iOS 27, *) {
          let compatible = AnimatedArtwork.compatibleAspectRatios
          let square = compatible.contains(.square)
          if square, compatible.contains(.tall) {
            // The idiom is main-actor API; every caller runs on the main actor.
            return MainActor.assumeIsolated {
              UIDevice.current.userInterfaceIdiom == .pad ? .square : .portrait
            }
          }
          return square ? .square : .portrait
        }
      #endif
      return Set(MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys)
        .contains(AnimatedArtworkKey.square.rawValue) ? .square : .portrait
    }
  }

  func animatedArtworkResources(for preset: Preset) -> (loopURL: URL, previewImage: UIImage)? {
    guard let animatedRef = preset.animatedArtwork,
      let loopPath = animatedRef.loopPath
    else {
      return nil
    }

    let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
    guard FileManager.default.fileExists(atPath: loopURL.path) else {
      return nil
    }

    let previewPath = animatedRef.previewPath ?? preset.staticArtworkPath
    guard let previewPath,
      FileManager.default.fileExists(
        atPath: AnimatedArtworkFileStore.absoluteURL(for: previewPath).path)
    else {
      return nil
    }

    let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
    guard let preview = UIImage(contentsOfFile: previewURL.path) else {
      return nil
    }

    return (loopURL, preview)
  }

#endif
