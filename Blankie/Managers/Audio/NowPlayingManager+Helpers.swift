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
  func soundNameSummary(_ titles: [String]) -> String { Self.soundNameSummary(titles) }

  /// The single source of the subtitle rule — shared by the lock screen and the
  /// widget subtitle so a budget/wording change can't diverge the two. Declared
  /// `nonisolated static` so the widget-catalog builder can reach it off-actor.
  nonisolated static func soundNameSummary(_ titles: [String]) -> String {
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

  /// Rasterize the shared `FallbackArtwork` fallback into lock-screen / CarPlay
  /// artwork. Rendered full-bleed (cornerRadius 0) since the system rounds the
  /// corners itself.
  private func fallbackArtworkImage(glyph: FallbackArtwork.Glyph, fraction: CGFloat)
    -> MPMediaItemArtwork?
  {
    let side: CGFloat = 512
    // Match the library / Now Playing artwork tint: the active preset's accent,
    // falling back to the app accent (themingPreset is nil during solo / Quick
    // Mix, so those correctly use the app accent).
    let accent =
      PresetManager.shared.themingPreset?.accentColor
      ?? GlobalSettings.shared.customAccentColor ?? .accentColor
    let view = FallbackArtwork(
      glyph: glyph,
      accent: accent,
      size: side,
      cornerRadius: 0,
      glyphFraction: fraction
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    renderer.isOpaque = true
    #if os(iOS) || os(visionOS)
      guard let image = renderer.uiImage else { return nil }
      return Self.makeArtwork(from: image)
    #elseif os(macOS)
      guard let image = renderer.nsImage else { return nil }
      return Self.makeArtwork(from: image)
    #else
      return nil
    #endif
  }

  /// A soloed sound's lock-screen artwork: its SF Symbol in the accent on the
  /// dark tinted card, mirroring the in-app placeholder.
  func soloArtwork(for sound: Sound) -> MPMediaItemArtwork? {
    fallbackArtworkImage(glyph: .symbol(sound.systemIconName), fraction: 0.4)
  }

  /// The fallback shown when a preset/mix has no custom or animated artwork:
  /// Quick Mix → grid, "All Blankie Sounds" → the Blankie mark, a custom preset
  /// → a montage of its playing sounds — matching the preset's library tile.
  func loadArtwork() -> MPMediaItemArtwork? {
    let glyph = FallbackArtwork.Glyph.playback(
      isQuickMix: AudioManager.shared.isQuickMix,
      isDefaultPreset: PresetManager.shared.currentPreset?.isDefault ?? true,
      icons: AudioManager.shared.playingSoundIcons())
    return fallbackArtworkImage(glyph: glyph, fraction: 0.5)
  }
}
