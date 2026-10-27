//
//  NowPlayingDisplay.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  What Now Playing shows, independent of how it's published, so the MediaPlayer
//  backend and the OS 27 one share the same rules.

import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Display rules shared by every Now Playing backend.
@MainActor
enum NowPlayingDisplay {

  // MARK: - Title and artist

  static func getDisplayInfo(
    presetName: String?, creatorName: String? = nil, preset: Preset? = nil
  ) -> (
    title: String, artist: String
  ) {
    if let singleSound = AudioManager.shared.singleSound {
      // A built-in sound's caption is the best second line. Custom sounds have no
      // caption, so they show their creator. The app name is the last resort.
      let artist =
        singleSound.localizedSubtitle ?? (singleSound.isCustom ? singleSound.creditedAuthor : nil)
        ?? "Blankie"
      return (title: singleSound.localizedTitle, artist: artist)
    } else if AudioManager.shared.isQuickMix {
      // Quick Mix has no preset, so name it explicitly (not "Custom Mix").
      let artistInfo = soundNameSummary(currentMixSoundTitles())
      return (title: String(localized: "Quick Mix"), artist: artistInfo)
    } else if let preset {
      return (title: preset.displayName, artist: getArtistInfo(creatorName: creatorName))
    } else if let name = presetName {
      // A name-only legacy call has no preset identity, so handle its internal
      // default name while preserving the existing fallback for generated names.
      let displayTitle: String
      if name == "Default" {
        displayTitle = String(localized: "All Blankie Sounds")
      } else if !name.starts(with: "Preset ") {
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
    // Creator name wins. Otherwise, list the sounds currently in the mix.
    if let creator = creatorName {
      return creator
    }
    return soundNameSummary(currentMixSoundTitles())
  }

  /// Titles of the switched-on sounds in the preset's display order (as in the mixer).
  /// Filters on selection, not `isPlaying`: a deselected sound renders through its fade-out.
  static func currentMixSoundTitles() -> [String] {
    AudioManager.shared.orderedVisibleSounds(
      for: AudioManager.shared.isQuickMix ? nil : PresetManager.shared.currentPreset
    )
    .filter { $0.isSelected }
    .map { $0.localizedTitle }
  }

  /// The one subtitle rule for the lock screen, CarPlay and the widget: the mix's
  /// sound names while they fit a character budget, else a count ("6 sounds"),
  /// because those system labels hard-truncate mid-word ("Grass St…").
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

  /// The widget's second line. Where `getDisplayInfo` falls back to "Blankie" for
  /// the lock screen, the widget shows no second line.
  static func widgetSubtitle(resolvedCreatorName: String?) -> String? {
    if let singleSound = AudioManager.shared.singleSound {
      return singleSound.isCustom ? singleSound.creditedAuthor : nil
    } else if let creator = resolvedCreatorName, !AudioManager.shared.isQuickMix {
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
  /// audio, then the single sound, then the longest selected sound's loop.
  static func currentProgressAnchor() -> (elapsed: TimeInterval, duration: TimeInterval)? {
    let sleepTimer = TimerManager.shared
    if sleepTimer.isTimerActive, sleepTimer.selectedDuration > 0 {
      let elapsed = sleepTimer.selectedDuration - sleepTimer.remainingTime
      return (max(0, elapsed), sleepTimer.selectedDuration)
    }

    let anchorSound: Sound?
    if let singleSound = AudioManager.shared.singleSound {
      anchorSound = singleSound
    } else {
      // The longest selected sound (not only playing ones), so time still tracks
      // while paused.
      anchorSound =
        AudioManager.shared.sounds
        .filter { $0.isSelected }
        .max { $0.playbackDuration < $1.playbackDuration }
    }

    // Under a second, a 0.25 s position poll can't see the wrap (it needs a
    // 0.5 s drop), so the bar would run past the end. Show it indeterminate.
    guard let anchorSound, anchorSound.playbackDuration >= 1 else { return nil }
    return (anchorSound.playbackPosition, anchorSound.playbackDuration)
  }

  // MARK: - Animated artwork

  #if os(iOS)
    /// Whether the lock screen should get an animated background at all: the
    /// user's setting, Reduce Motion, and Low Power Mode each veto it.
    static func shouldPublishAnimatedArtwork() -> Bool {
      GlobalSettings.shared.lockScreenBackgroundEnabled
        && !UIAccessibility.isReduceMotionEnabled
        && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  #endif

  // MARK: - Fallback artwork

  /// Rasterizes `FallbackArtwork` for the lock screen and CarPlay. Full-bleed
  /// (cornerRadius 0) because the system rounds the corners itself.
  private static func fallbackArtworkImage(glyph: FallbackArtwork.Glyph, fraction: CGFloat)
    -> PlatformImage?
  {
    let side: CGFloat = 512
    // The active preset's accent, else the app accent (themingPreset is nil during
    // single sound and Quick Mix), matching the in-app artwork tint.
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

  /// A single sound's lock-screen artwork: its SF Symbol in the accent on the
  /// dark tinted card, mirroring the in-app placeholder.
  static func singleFallbackImage(for sound: Sound) -> PlatformImage? {
    fallbackArtworkImage(glyph: .symbol(sound.systemIconName), fraction: 0.4)
  }

  /// The fallback for a mix without custom or animated artwork, matching its library
  /// tile: the Quick Mix glyph, the Blankie mark for "All Blankie Sounds", or a
  /// montage of a custom preset's playing sounds.
  static func mixFallbackImage(_ glyph: FallbackArtwork.Glyph = mixFallbackGlyph())
    -> PlatformImage?
  {
    fallbackArtworkImage(glyph: glyph, fraction: 0.5)
  }

  /// The glyph `mixFallbackImage()` draws for the live playback state.
  static func mixFallbackGlyph() -> FallbackArtwork.Glyph {
    .playback(
      isQuickMix: AudioManager.shared.isQuickMix,
      isDefaultPreset: PresetManager.shared.currentPreset?.isDefault ?? true,
      icons: AudioManager.shared.playingSoundIcons())
  }
}
