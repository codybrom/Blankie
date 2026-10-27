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

  /// Wraps a pre-rendered image in `MPMediaItemArtwork`. `nonisolated` so the handler
  /// doesn't inherit `@MainActor`. MediaPlayer calls it from a background queue.
  #if os(iOS) || os(visionOS)
    nonisolated static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
  #elseif os(macOS)
    nonisolated static func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
  #endif

  /// A single sound's lock-screen artwork: the shared fallback image wrapped for
  /// MediaPlayer.
  func singleArtwork(for sound: Sound) -> MPMediaItemArtwork? {
    guard let image = NowPlayingDisplay.singleFallbackImage(for: sound) else { return nil }
    return Self.makeArtwork(from: image)
  }

  /// The mix's fallback artwork, wrapped for MediaPlayer.
  func loadArtwork(
    glyph: FallbackArtwork.Glyph = NowPlayingDisplay.mixFallbackGlyph()
  ) -> MPMediaItemArtwork? {
    guard let image = NowPlayingDisplay.mixFallbackImage(glyph) else { return nil }
    return Self.makeArtwork(from: image)
  }
}
