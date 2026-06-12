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
      // Built-in sound authors are shown in the dedicated credits screens, but for user-added sounds show the creator name if available
      let artist = (soloSound.isCustom ? soloSound.creditedAuthor : nil) ?? "Blankie"
      return (title: soloSound.title, artist: artist)
    } else if AudioManager.shared.isQuickMix {
      // Quick Mix has no preset of its own; name it explicitly rather than
      // letting it fall through to the generic "Custom Mix".
      let artistInfo = getArtistInfo(creatorName: creatorName)
      return (title: String(localized: "Quick Mix"), artist: artistInfo)
    } else if let name = presetName {
      // Handle special presets
      let displayTitle: String
      if name != "Default" && !name.starts(with: "Preset ") {
        displayTitle = name
      } else {
        displayTitle = String(localized: "Custom Mix")
      }

      let artistInfo = getArtistInfo(creatorName: creatorName)
      return (title: displayTitle, artist: artistInfo)
    } else {
      let artistInfo = getArtistInfo(creatorName: creatorName)
      return (title: String(localized: "Custom Mix"), artist: artistInfo)
    }
  }

  private func getArtistInfo(creatorName: String? = nil) -> String {
    // Creator name wins; otherwise list the sounds currently in the mix.
    if let creator = creatorName {
      return creator
    }
    return soundNameSummary(currentMixSoundTitles())
  }

  /// Titles of the sounds currently in the mix, in the preset's display order
  /// (the same `orderedVisibleSounds` order as the mixer grid), filtered to the
  /// ones switched on. Selection is the on/off truth — a just-deselected sound
  /// keeps rendering through its fade-out, so filtering on `isPlaying` would
  /// leave it listed after the user turned it off.
  func currentMixSoundTitles() -> [String] {
    AudioManager.shared.orderedVisibleSounds(for: PresetManager.shared.currentPreset)
      .filter { $0.isSelected }
      .map { $0.title }
  }

  /// One metadata line for the lock screen / CarPlay from the mix's sound names.
  /// Those labels are system-rendered with no width API and hard-truncate
  /// mid-word ("Grass St…"). A short mix shows its names in full; once the list
  /// would overflow a conservative character budget, fall back to a single
  /// count ("6 sounds") — clean, and trivially localizable as one plural string.
  func soundNameSummary(_ titles: [String]) -> String {
    guard !titles.isEmpty else { return "Blankie" }
    let joined = titles.joined(separator: ", ")
    let budget = 50
    // The count branch is only reached with 2+ names, so the plural is safe.
    if joined.count <= budget || titles.count == 1 { return joined }
    return String(localized: "\(titles.count) sounds")
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

      let format = UIGraphicsImageRendererFormat.preferred()
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: side), format: format)
      let image = renderer.image { _ in
        UIColor(white: 0.11, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
        let target = symbol.size
        symbol.draw(at: CGPoint(x: (side - target.width) / 2, y: (side - target.height) / 2))
      }
      return Self.makeArtwork(from: image)
    #else
      return nil
    #endif
  }

  func loadArtwork() -> MPMediaItemArtwork? {
    #if os(iOS) || os(visionOS)
      let side: CGFloat = 512
      let accent = GlobalSettings.shared.customAccentColor
      let accentColor = accent ?? Color.accentColor

      // Render the same BrandedBlankieIcon view used in-app so the palette
      // gradient and inner circles look identical on the lock screen / CarPlay.
      let card = ZStack {
        Color(white: 0.11)
        BrandedBlankieIcon(size: side * 0.5, color: accentColor)
      }
      .frame(width: side, height: side)

      let renderer = ImageRenderer(content: card)
      renderer.scale = 1
      renderer.isOpaque = true
      guard let image = renderer.uiImage else { return nil }
      return Self.makeArtwork(from: image)
    #elseif os(macOS)
      let side: CGFloat = 512
      let accent = GlobalSettings.shared.customAccentColor
      let accentColor = accent ?? Color.accentColor

      let card = ZStack {
        Color(white: 0.11)
        BrandedBlankieIcon(size: side * 0.5, color: accentColor)
      }
      .frame(width: side, height: side)

      let renderer = ImageRenderer(content: card)
      renderer.scale = 1
      renderer.isOpaque = true
      guard let image = renderer.nsImage else { return nil }
      return Self.makeArtwork(from: image)
    #else
      return nil
    #endif
  }
}
