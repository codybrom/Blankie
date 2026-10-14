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

    /// The variant this device's lock screen actually displays: iPad advertises
    /// only the 1x1 key, iPhone the 3x4 key. The gallery and in-app preview key
    /// off this (not the device idiom) so they match what the lock screen shows
    /// and so iPad downloads only the square pack, never both variants.
    /// On 27 the NowPlaying framework answers the same question, and mixing it
    /// with MediaPlayer for local playback is undefined — so ask whichever
    /// framework owns the card. A device that takes both crops still prefetches
    /// and previews one, by idiom: the outcome the 26 keys already produced.
    nonisolated static var preferredForDevice: AnimatedArtworkKey {
      #if canImport(NowPlaying)
        if #available(iOS 27, *) {
          let compatible = AnimatedArtwork.compatibleAspectRatios
          let square = compatible.contains(.square)
          if square, compatible.contains(.tall) {
            // The idiom is main-actor API and every caller reaches this from the
            // main actor (the prefetch mapping runs inside a main-actor task).
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
