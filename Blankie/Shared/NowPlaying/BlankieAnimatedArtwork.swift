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

  enum AnimatedArtworkKey: String {
    case square = "MPNowPlayingInfoProperty1x1AnimatedArtwork"
    case portrait = "MPNowPlayingInfoProperty3x4AnimatedArtwork"

    /// The variant this device's lock screen actually displays: iPad advertises
    /// only the 1x1 key, iPhone the 3x4 key. The gallery and in-app preview key
    /// off this (not the device idiom) so they match what the lock screen shows
    /// and so iPad downloads only the square pack, never both variants.
    static var preferredForDevice: AnimatedArtworkKey {
      Set(MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys)
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
