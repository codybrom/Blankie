//
//  NowPlayingManager+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import AVFoundation
import MediaPlayer
import SwiftUI

extension NowPlayingManager {

  /// The mix's subtitle rule, reachable off-actor where callers already name
  /// `NowPlayingManager` (`AudioManager+Widgets`, the widget-catalog builder).
  nonisolated static func soundNameSummary(_ titles: [String]) -> String {
    NowPlayingDisplay.soundNameSummary(titles)
  }

  func loadCustomArtwork(from data: Data?) -> MPMediaItemArtwork? {
    guard let artworkData = data else { return nil }

    #if os(iOS) || os(visionOS)
      if let image = UIImage(data: artworkData) {
        return Self.makeArtwork(from: image)
      }
    #elseif os(macOS)
      if let image = NSImage(data: artworkData) {
        return Self.makeArtwork(from: image)
      }
    #endif
    return nil
  }

  /// Wraps a pre-rendered image in `MPMediaItemArtwork`. Declared `nonisolated`
  /// so the request handler closure does NOT inherit `NowPlayingManager`'s
  /// `@MainActor` isolation — MediaPlayer invokes that handler from a background
  /// queue, and an isolated closure would force an `unsafeForcedSync` hop.
  #if os(iOS) || os(visionOS)
    nonisolated static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
  #elseif os(macOS)
    nonisolated static func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
  #endif

  /// A soloed sound's lock-screen artwork: the shared fallback image wrapped for
  /// MediaPlayer.
  func soloArtwork(for sound: Sound) -> MPMediaItemArtwork? {
    guard let image = NowPlayingDisplay.soloFallbackImage(for: sound) else { return nil }
    return Self.makeArtwork(from: image)
  }

  /// The mix's fallback artwork, wrapped for MediaPlayer.
  func loadArtwork() -> MPMediaItemArtwork? {
    guard let image = NowPlayingDisplay.mixFallbackImage() else { return nil }
    return Self.makeArtwork(from: image)
  }
}
