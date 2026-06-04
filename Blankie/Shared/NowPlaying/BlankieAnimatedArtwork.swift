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
