//
//  AudioManager+PlayableItem.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//
//  The single resolution service for a PlayableItem's display fields — the
//  name / icon / subtitle / accent / thumbnail every favorites surface (widget,
//  CarPlay) used to re-derive by hand from a raw token. Domain-object surfaces
//  (the in-app Library, media-control navigation) parse with `PlayableItem`
//  directly and resolve to the Preset/Sound they need, so they don't route
//  through here.
//

import Foundation

/// The per-surface display fields for a `PlayableItem`, resolved once.
struct PlayableItemDisplay {
  var displayName: String
  var systemIconName: String
  var subtitle: String?
  var accentColorName: String?
  var thumbnailKey: String?
}

extension AudioManager {
  /// Resolves a `PlayableItem` to its display fields, or nil when it points at a
  /// sound/preset that no longer exists (a dead token). Non-preset items have no
  /// accent of their own, so they use the app's `customAccentColor` — the same
  /// fallback the live playback accent resolves to (see `widgetFavorite`).
  @MainActor
  func display(for item: PlayableItem) -> PlayableItemDisplay? {
    let appAccent = GlobalSettings.shared.customAccentColor?.toString
    switch item {
    case .allSounds:
      return PlayableItemDisplay(
        displayName: String(localized: "All Blankie Sounds"),
        systemIconName: "square.grid.2x2",
        subtitle: nil,
        accentColorName: appAccent,
        thumbnailKey: nil)
    case .quickMix:
      return PlayableItemDisplay(
        displayName: String(localized: "Quick Mix"),
        systemIconName: "shuffle",
        subtitle: nil,
        accentColorName: appAccent,
        thumbnailKey: nil)
    case .solo(let fileName):
      guard let soloSound = sound(fileName: fileName) else { return nil }
      return PlayableItemDisplay(
        displayName: soloSound.localizedTitle,
        systemIconName: soloSound.systemIconName,
        subtitle: soloSound.isCustom ? soloSound.creditedAuthor : nil,
        accentColorName: appAccent,
        thumbnailKey: nil)
    case .preset(let id):
      guard let preset = PresetManager.shared.presets.first(where: { $0.id == id }) else {
        return nil
      }
      return PlayableItemDisplay(
        displayName: preset.displayName,
        systemIconName: "square.stack.3d.up.fill",
        subtitle: presetSubtitle(for: preset),
        accentColorName: preset.accentColorName,
        thumbnailKey: "preset_thumb_\(preset.id.uuidString)")
    }
  }
}
