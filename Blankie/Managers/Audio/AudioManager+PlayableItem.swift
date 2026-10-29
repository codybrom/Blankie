//
//  AudioManager+PlayableItem.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//
//  Resolves a PlayableItem's display fields (name, icon, subtitle, accent,
//  thumbnail) for favorites surfaces such as widgets and CarPlay. In-app
//  surfaces resolve `PlayableItem` to a Preset or Sound directly.
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
  /// What drives the mixer: single sound, then an unsaved mix, then Quick Mix, then the
  /// current preset (the default reads as `.allSounds`). `PresetManager.themingPreset` uses
  /// the same order.
  @MainActor
  var activeItem: PlayableItem? {
    if let singleSound = singleSound {
      return .single(fileName: singleSound.fileName)
    }
    if unsavedMix != nil {
      return .unsavedMix
    }
    if isQuickMix {
      return .quickMix
    }
    if let preset = PresetManager.shared.currentPreset {
      return preset.isDefault ? .allSounds : .preset(preset.id)
    }
    return nil
  }

  /// Display fields for an item, or nil when its sound or preset is gone. Non-preset
  /// items use the app's `customAccentColor`, matching the live playback accent.
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
    case .single(let fileName):
      guard let singleSound = sound(fileName: fileName) else { return nil }
      return PlayableItemDisplay(
        displayName: singleSound.localizedTitle,
        systemIconName: singleSound.systemIconName,
        subtitle: singleSound.isCustom ? singleSound.creditedAuthor : nil,
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
    case .unsavedMix:
      return nil
    }
  }
}
