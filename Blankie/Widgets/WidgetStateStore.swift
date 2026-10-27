//
//  WidgetStateStore.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import Foundation
import WidgetKit

/// Playback state the widgets render. The extension reads this App Group snapshot
/// and never touches `AudioManager` or `PresetManager`.
struct WidgetPlaybackState: Codable, Equatable {
  var isPlaying: Bool
  var title: String
  var subtitle: String?
  var soundSystemIconNames: [String]
  /// Cached `preset_thumb_<uuid>` artwork key. Nil for single sound, Quick Mix and the
  /// default preset. The widget falls back to the icon.
  var thumbnailKey: String?
  /// The `starredItems` token for what's active, so a favorites tile can tell
  /// it's the one playing (or paused).
  var activeToken: String?
  /// `Color.toString` name of the preset's accent, or the app accent when it has none.
  var accentColorName: String?
}

struct WidgetFavorite: Codable, Equatable, Identifiable {
  var id: String { token }
  /// A `GlobalSettings.starredItems` token: a preset's UUID string,
  /// `allSoundsToken`, `quickMixToken`, or a `solo:<fileName>` token.
  var token: String
  var displayName: String
  var systemIconName: String
  /// Cached `preset_thumb_<uuid>` artwork key, for presets with artwork.
  var thumbnailKey: String?
  /// `Color.toString` name of the preset's own accent, if set.
  var accentColorName: String?
  /// Creator name or sound list, using `NowPlayingManager`'s fallback so pinned
  /// and playing widgets match.
  var subtitle: String?

  var isSingleSound: Bool {
    if case .single = PlayableItem(token: token) { return true }
    return false
  }
}

/// A sound from `GlobalSettings.quickMixSoundFileNames`, for the Quick Mix widget.
struct WidgetQuickMixSound: Codable, Equatable, Identifiable {
  var id: String { fileName }
  var fileName: String
  var displayName: String
  var systemIconName: String
  /// True only while Quick Mix is active and includes this sound.
  var isSelected: Bool
  /// Optional so snapshots written before XL volume controls remain decodable.
  var volume: Float? = nil

  var volumePercent: Int {
    let value = volume ?? 0.8
    return value.isFinite ? Int((min(1, max(0, value)) * 100).rounded()) : 80
  }
}

struct WidgetSnapshot: Codable, Equatable {
  var playback: WidgetPlaybackState
  var favorites: [WidgetFavorite]
  var quickMixSounds: [WidgetQuickMixSound]
  /// Every preset and every sound that can play on its own for the Pinned Sound picker, starred
  /// or not.
  var pinnableItems: [WidgetFavorite]
  /// The user's app accent (`GlobalSettings.customAccentColor`), for the Quick Mix
  /// widget. Can differ from the widget bundle's static AccentColor asset.
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

  /// Lets `publish` skip unchanged snapshots (the Now Playing tick republishes often).
  @MainActor private static var lastPublished: WidgetSnapshot?

  /// Writes the snapshot and reloads every widget timeline. No-op when unchanged.
  @MainActor
  static func publish(_ snapshot: WidgetSnapshot) {
    guard snapshot != lastPublished else { return }
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.shared.set(data, forKey: key)
    lastPublished = snapshot
    WidgetCenter.shared.reloadAllTimelines()
  }

  /// Reloads directly: the snapshot holds only the artwork key, so `publish` sees no change.
  static func artworkDidChange() {
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
