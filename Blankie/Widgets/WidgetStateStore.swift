//
//  WidgetStateStore.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import Foundation
import WidgetKit

/// What the Home Screen widgets and Control Center controls render. The
/// widget extension process never touches `AudioManager`/`PresetManager`
/// (AVFoundation, SwiftData) directly for rendering — it reads this cached
/// snapshot from the App Group instead. The app rebuilds and republishes it
/// whenever playback or favorites change.
struct WidgetPlaybackState: Codable, Equatable {
  var isPlaying: Bool
  var title: String
  var subtitle: String?
  var soundSystemIconNames: [String]
  /// Key into the App Group's cached `preset_thumb_<uuid>` artwork, when the
  /// current preset has cached artwork. Nil for solo/Quick Mix/no-artwork.
  var thumbnailKey: String?
  /// The `starredItems` token (if any) matching what's currently active —
  /// preset UUID string, `allSoundsToken`, `quickMixToken`, or a
  /// `solo:<fileName>` token — so a favorites tile can tell it's the one
  /// that's playing (or paused-but-loaded) without comparing titles.
  var activeToken: String?
  /// `Color.toString` name (see `Color+Extension`) of the current preset's
  /// accent, or the app-wide accent when the preset has none. Widgets theme
  /// their background with this instead of a fixed color, matching how the
  /// app itself tints per preset.
  var accentColorName: String?
}

struct WidgetFavorite: Codable, Equatable, Identifiable {
  var id: String { token }
  /// A `GlobalSettings.starredItems` token: a preset's UUID string,
  /// `allSoundsToken`, `quickMixToken`, or a `solo:<fileName>` token.
  var token: String
  var displayName: String
  var systemIconName: String
  /// Key into the App Group's cached `preset_thumb_<uuid>` artwork, when this
  /// favorite is backed by a preset with cached artwork.
  var thumbnailKey: String?
  /// `Color.toString` name of this favorite's own accent, when it's a preset
  /// with one set.
  var accentColorName: String?
  /// Creator name, or the preset's own sound list, matching the same
  /// fallback chain `NowPlayingManager` resolves for the currently-playing
  /// widget — so a pinned preset and that same preset actually playing show
  /// the same secondary line instead of one having it and the other not.
  var subtitle: String?
}

/// One of the sounds in `GlobalSettings.quickMixSoundFileNames`, for the
/// dedicated Quick Mix widget's toggle grid.
struct WidgetQuickMixSound: Codable, Equatable, Identifiable {
  var id: String { fileName }
  var fileName: String
  var displayName: String
  var systemIconName: String
  /// True when this sound is currently part of an active Quick Mix — not
  /// just "selected" (a sound can be selected via a regular preset without
  /// Quick Mix being active at all).
  var isSelected: Bool
}

struct WidgetSnapshot: Codable, Equatable {
  var playback: WidgetPlaybackState
  var favorites: [WidgetFavorite]
  var quickMixSounds: [WidgetQuickMixSound]
  /// Every preset (not just starred ones) plus every solo-able sound, for
  /// the Pinned Sound widget's configuration picker — pinning one specific
  /// thing to the Home Screen shouldn't require starring it first, unlike
  /// the Favorites widget/Control, which are intentionally starred-only.
  var pinnableItems: [WidgetFavorite]
  /// The app's own accent (`GlobalSettings.customAccentColor`), for widgets
  /// with no preset/sound of their own to theme with — the Quick Mix widget.
  /// Not the same as the widget target's static `Color("AccentColor")` asset:
  /// that's a fixed fallback color baked into the widget bundle, while this
  /// is the user's actual chosen accent, the same one `playback.accentColorName`
  /// falls back to for the currently-playing widget.
  var defaultAccentColorName: String?

  static let empty = WidgetSnapshot(
    playback: WidgetPlaybackState(
      isPlaying: false, title: "Blankie", subtitle: nil, soundSystemIconNames: [],
      thumbnailKey: nil, activeToken: nil, accentColorName: nil),
    favorites: [],
    quickMixSounds: [],
    pinnableItems: [],
    defaultAccentColorName: nil
  )
}

enum WidgetStateStore {
  private static let key = "widgetSnapshot"

  /// Called by the app whenever playback or favorites change. Reloads every
  /// widget/Control timeline so the new snapshot renders immediately — the
  /// single choke point, so callers never forget the reload half of the pair.
  static func publish(_ snapshot: WidgetSnapshot) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.shared.set(data, forKey: key)
    WidgetCenter.shared.reloadAllTimelines()
  }

  static func current() -> WidgetSnapshot {
    guard let data = UserDefaults.shared.data(forKey: key),
      let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    else {
      return .empty
    }
    return snapshot
  }
}
