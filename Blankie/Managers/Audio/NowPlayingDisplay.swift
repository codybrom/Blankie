//
//  NowPlayingDisplay.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  What Now Playing shows, with nothing about how it is published — so both the
//  MediaPlayer backend and its OS 27 replacement read the same rules.

import SwiftUI

/// Display rules shared by every Now Playing backend.
@MainActor
enum NowPlayingDisplay {

  // MARK: - Title and artist

  static func getDisplayInfo(presetName: String?, creatorName: String? = nil) -> (
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

  private static func getArtistInfo(creatorName: String? = nil) -> String {
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
  static func currentMixSoundTitles() -> [String] {
    AudioManager.shared.orderedVisibleSounds(for: PresetManager.shared.currentPreset)
      .filter { $0.isSelected }
      .map { $0.title }
  }

  /// One metadata line for the lock screen / CarPlay from the mix's sound names.
  /// Those labels are system-rendered with no width API and hard-truncate
  /// mid-word ("Grass St…"). A short mix shows its names in full; once the list
  /// would overflow a conservative character budget, fall back to a single
  /// count ("6 sounds") — clean, and trivially localizable as one plural string.
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

  // MARK: - Album and widget lines

  /// "20 Minute Timer" / "1 Hour Timer" / "1 Hour 30 Minute Timer" from the
  /// timer's total duration (adjectival singular, matching the in-app phrasing).
  static func timerAlbumLabel() -> String {
    let total = Int(TimerManager.shared.selectedDuration.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    // This shows on the lock screen of a multi-language app, so localize each
    // shape (translators can reorder the placeholders / set plurals per locale).
    if hours > 0, minutes > 0 {
      return String(localized: "\(hours) Hour \(minutes) Minute Timer")
    } else if hours > 0 {
      return String(localized: "\(hours) Hour Timer")
    } else if minutes > 0 {
      return String(localized: "\(minutes) Minute Timer")
    } else {
      return String(localized: "Timer")
    }
  }

  /// The widget's second line. `getDisplayInfo`'s artist synthesizes "Blankie"
  /// as a fallback in several places (solo built-in sounds, an empty sound list)
  /// so the lock screen never shows a blank artist line — the widget should
  /// never repeat that synthesized text as a second line; no real info means no
  /// second line.
  static func widgetSubtitle(resolvedCreatorName: String?) -> String? {
    if let soloSound = AudioManager.shared.soloModeSound {
      return soloSound.isCustom ? soloSound.creditedAuthor : nil
    } else if AudioManager.shared.isQuickMix {
      return resolvedCreatorName
    } else if let creator = resolvedCreatorName {
      return creator
    } else {
      let titles = currentMixSoundTitles()
      return titles.isEmpty ? nil : soundNameSummary(titles)
    }
  }

  // MARK: - Progress

  /// The elapsed/duration the scrubber should represent right now, or `nil` for
  /// an indeterminate bar. Priority: an active sleep timer (real, slow,
  /// meaningful progress that ends where playback stops) wins over the looping
  /// audio, then the solo sound, then the longest selected sound's loop.
  static func currentProgressAnchor() -> (elapsed: TimeInterval, duration: TimeInterval)? {
    let sleepTimer = TimerManager.shared
    if sleepTimer.isTimerActive, sleepTimer.selectedDuration > 0 {
      let elapsed = sleepTimer.selectedDuration - sleepTimer.remainingTime
      return (max(0, elapsed), sleepTimer.selectedDuration)
    }

    let anchorSound: Sound?
    if let soloSound = AudioManager.shared.soloModeSound {
      anchorSound = soloSound
    } else {
      // Use active (selected) sounds, not only playing ones, so we still track
      // time when paused; mirror the "longest selected sound" choice.
      anchorSound =
        AudioManager.shared.sounds
        .filter { $0.isSelected }
        .max { $0.playbackDuration < $1.playbackDuration }
    }

    guard let anchorSound, anchorSound.playbackDuration > 0 else { return nil }
    return (anchorSound.playbackPosition, anchorSound.playbackDuration)
  }

  // MARK: - Fallback artwork

  /// Rasterize the shared `FallbackArtwork` fallback into lock-screen / CarPlay
  /// artwork. Rendered full-bleed (cornerRadius 0) since the system rounds the
  /// corners itself.
  private static func fallbackArtworkImage(glyph: FallbackArtwork.Glyph, fraction: CGFloat)
    -> PlatformImage?
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
      return renderer.uiImage
    #elseif os(macOS)
      return renderer.nsImage
    #else
      return nil
    #endif
  }

  /// A soloed sound's lock-screen artwork: its SF Symbol in the accent on the
  /// dark tinted card, mirroring the in-app placeholder.
  static func soloFallbackImage(for sound: Sound) -> PlatformImage? {
    fallbackArtworkImage(glyph: .symbol(sound.systemIconName), fraction: 0.4)
  }

  /// The fallback shown when a preset/mix has no custom or animated artwork:
  /// Quick Mix → grid, "All Blankie Sounds" → the Blankie mark, a custom preset
  /// → a montage of its playing sounds — matching the preset's library tile.
  static func mixFallbackImage() -> PlatformImage? {
    let glyph = FallbackArtwork.Glyph.playback(
      isQuickMix: AudioManager.shared.isQuickMix,
      isDefaultPreset: PresetManager.shared.currentPreset?.isDefault ?? true,
      icons: AudioManager.shared.playingSoundIcons())
    return fallbackArtworkImage(glyph: glyph, fraction: 0.5)
  }
}
