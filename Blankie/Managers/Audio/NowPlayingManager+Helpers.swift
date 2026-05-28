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

  func getDisplayInfo(presetName: String?, creatorName: String? = nil) -> (
    title: String, artist: String
  ) {
    // Check if we're in solo mode
    if let soloSound = AudioManager.shared.soloModeSound {
      // Check if the sound has a creator/credited author
      let artist: String
      if let author = SoundCreditsManager.shared.getAuthor(for: soloSound.title),
        !author.isEmpty
      {
        artist = "Sound by \(author)"
      } else {
        artist = "Blankie"
      }
      return (title: soloSound.title, artist: artist)
    } else if let name = presetName {
      // Handle special presets
      let displayTitle: String
      if name == "Quick Mix (CarPlay)" {
        displayTitle = "Quick Mix"
      } else if name != "Default" && !name.starts(with: "Preset ") {
        displayTitle = name
      } else {
        displayTitle = "Custom Mix"
      }

      let artistInfo = getArtistInfo(creatorName: creatorName)
      return (title: displayTitle, artist: artistInfo)
    } else {
      let artistInfo = getArtistInfo(creatorName: creatorName)
      return (title: "Custom Mix", artist: artistInfo)
    }
  }

  private func getArtistInfo(creatorName: String? = nil) -> String {
    // If creator name is provided, show it first
    if let creator = creatorName {
      return creator
    }

    // Otherwise show active sounds
    let activeSounds = AudioManager.shared.sounds.filter { $0.isSelected }
    if !activeSounds.isEmpty {
      let soundNames = activeSounds.map { $0.title }.joined(separator: ", ")
      return soundNames
    } else {
      return "Blankie"
    }
  }

  func loadCustomArtwork(from data: Data?) -> MPMediaItemArtwork? {
    guard let artworkData = data else { return nil }

    #if os(iOS) || os(visionOS)
      if let image = UIImage(data: artworkData) {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
      }
    #elseif os(macOS)
      if let image = NSImage(data: artworkData) {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
      }
    #endif
    return nil
  }

  /// Render a soloed sound's SF Symbol into lock-screen artwork: the app-accent
  /// glyph centered on a dark card, mirroring the in-app placeholder. Returns
  /// nil on platforms where it isn't rendered (caller falls back to default).
  func soloArtwork(for sound: Sound) -> MPMediaItemArtwork? {
    #if os(iOS) || os(visionOS)
      let side: CGFloat = 512
      let accent = UIColor(GlobalSettings.shared.customAccentColor ?? Color.accentColor)
      let config = UIImage.SymbolConfiguration(pointSize: side * 0.4, weight: .regular)
      guard
        let symbol = UIImage(systemName: sound.systemIconName, withConfiguration: config)?
          .withTintColor(accent, renderingMode: .alwaysOriginal)
      else { return nil }

      let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
      let image = renderer.image { _ in
        UIColor(white: 0.11, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
        let target = symbol.size
        symbol.draw(at: CGPoint(x: (side - target.width) / 2, y: (side - target.height) / 2))
      }
      return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    #else
      return nil
    #endif
  }

  func loadArtwork() -> MPMediaItemArtwork? {
    #if os(iOS) || os(visionOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = UIImage(data: imageData)
      {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
      }
    #elseif os(macOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = NSImage(data: imageData)
      {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
      }
    #endif
    return nil
  }
}
