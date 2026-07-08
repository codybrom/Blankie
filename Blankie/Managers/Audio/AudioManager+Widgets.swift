//
//  AudioManager+Widgets.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import Foundation
import SwiftUI

extension AudioManager {
  /// Rebuilds and republishes the Home Screen widget / Control Center
  /// snapshot. Called from the same place `NowPlayingManager` republishes
  /// lock-screen info (`performNowPlayingUpdate`), so widget state stays in
  /// lockstep with it instead of drifting via a second set of call sites.
  @MainActor
  func publishWidgetSnapshot(
    title: String, subtitle: String?, isPlaying: Bool, thumbnailKey: String?,
    accentColorName: String?
  ) {
    let snapshot = WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: isPlaying,
        title: title,
        subtitle: subtitle,
        // Quick Mix's "now playing" icon is its own recognizable shuffle
        // glyph (matching the Favorites tile), not whichever individual
        // sound happens to be in the mix. Solo mode preserves other sounds'
        // `isSelected` state (it only mutes them), so `playingSoundIcons`
        // would otherwise pull in icons for sounds that aren't actually
        // playing — show only the soloed sound's own icon.
        soundSystemIconNames: {
          if let soloSound = soloModeSound { return [soloSound.systemIconName] }
          if isQuickMix { return ["shuffle"] }
          return playingSoundIcons(limit: 4)
        }(),
        thumbnailKey: thumbnailKey,
        activeToken: currentFavoriteToken,
        accentColorName: accentColorName ?? GlobalSettings.shared.customAccentColor?.toString
      ),
      favorites: GlobalSettings.shared.starredItems.compactMap(widgetFavorite(forToken:)),
      quickMixSounds: widgetQuickMixSounds(),
      pinnableItems: widgetPinnableItems(),
      defaultAccentColorName: GlobalSettings.shared.customAccentColor?.toString
    )
    WidgetStateStore.publish(snapshot)
  }

  /// Republish favorites/Quick Mix/pinnable/accent data after a settings change,
  /// carrying the last-published playback state so this never contradicts the
  /// Now Playing pipeline about what's playing.
  @MainActor
  func republishWidgetCatalog() {
    let last = WidgetStateStore.current().playback
    // Derive the accent from its source, not the last-published value: the
    // active preset's own accent when a preset is what's playing (matching the
    // Now Playing pipeline's `preset?.accentColorName`), otherwise the app-wide
    // custom accent — so a global-accent change is reflected immediately even
    // for a preset that has no accent of its own.
    let presetAccent =
      soloModeSound == nil && !isQuickMix
      ? PresetManager.shared.currentPreset?.accentColorName : nil
    let accentColorName = presetAccent ?? GlobalSettings.shared.customAccentColor?.toString
    let playback = WidgetPlaybackState(
      isPlaying: last.isPlaying,
      title: last.title,
      subtitle: last.subtitle,
      soundSystemIconNames: last.soundSystemIconNames,
      thumbnailKey: last.thumbnailKey,
      activeToken: currentFavoriteToken,
      accentColorName: accentColorName
    )
    let snapshot = WidgetSnapshot(
      playback: playback,
      favorites: GlobalSettings.shared.starredItems.compactMap(widgetFavorite(forToken:)),
      quickMixSounds: widgetQuickMixSounds(),
      pinnableItems: widgetPinnableItems(),
      defaultAccentColorName: GlobalSettings.shared.customAccentColor?.toString
    )
    WidgetStateStore.publish(snapshot)
  }

  /// Each of `GlobalSettings.quickMixSoundFileNames`, marked selected only
  /// when Quick Mix is the mode actually driving playback right now — a
  /// sound can be `isSelected` via a regular preset without that meaning
  /// anything for the Quick Mix widget.
  private func widgetQuickMixSounds() -> [WidgetQuickMixSound] {
    GlobalSettings.shared.quickMixSoundFileNames.compactMap { fileName in
      guard let quickMixSound = sound(fileName: fileName) else { return nil }
      return WidgetQuickMixSound(
        fileName: fileName,
        displayName: quickMixSound.localizedTitle,
        systemIconName: quickMixSound.systemIconName,
        isSelected: isQuickMix && quickMixSound.isSelected
      )
    }
  }

  /// Every preset plus every solo-able sound, for the Pinned Sound widget's
  /// configuration picker — unlike `favorites`, this isn't filtered by
  /// `starredItems`, since pinning one specific thing to the Home Screen
  /// shouldn't require starring it first. Mirrors CarPlay's
  /// `SoundsListTemplate` solo-eligibility filter (`!isPresetUseOnly`).
  private func widgetPinnableItems() -> [WidgetFavorite] {
    let presetItems = PresetManager.shared.presets.map { preset in
      WidgetFavorite(
        token: preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString,
        displayName: preset.displayName,
        systemIconName: "square.stack.3d.up.fill",
        thumbnailKey: "preset_thumb_\(preset.id.uuidString)",
        accentColorName: preset.accentColorName,
        subtitle: presetSubtitle(for: preset)
      )
    }
    let soundItems = sounds.filter { !$0.isPresetUseOnly }.map { sound in
      WidgetFavorite(
        token: GlobalSettings.soloToken(forFileName: sound.fileName),
        displayName: sound.localizedTitle,
        systemIconName: sound.systemIconName,
        thumbnailKey: nil,
        accentColorName: GlobalSettings.shared.customAccentColor?.toString,
        subtitle: sound.isCustom ? sound.creditedAuthor : nil
      )
    }
    return presetItems + soundItems
  }

  /// Creator name, or the preset's own configured sound list — the same
  /// fallback chain `NowPlayingManager`'s widget subtitle uses for whatever's
  /// currently playing, applied here to an arbitrary (possibly not currently
  /// active) preset so a pinned preset and that preset actually playing read
  /// the same way. Shares `NowPlayingManager.soundNameSummary` for the
  /// truncation rule (full list under budget, else a count), resolving an
  /// arbitrary preset's own stored sound states rather than the live mix.
  func presetSubtitle(for preset: Preset) -> String? {
    if let creator = preset.creatorName { return creator }
    let order = preset.soundOrder ?? preset.soundStates.map(\.fileName)
    let selected = Set(preset.soundStates.filter(\.isSelected).map(\.fileName))
    let titles = order.filter { selected.contains($0) }.compactMap {
      sound(fileName: $0)?.localizedTitle
    }
    guard !titles.isEmpty else { return nil }
    return NowPlayingManager.soundNameSummary(titles)
  }

  /// The `starredItems` token matching what's currently active, if any —
  /// resolved the same way `PresetManager.themingPreset` picks what's "in
  /// charge" of the mixer right now (solo, then Quick Mix, then preset).
  @MainActor
  var currentFavoriteToken: String? {
    if let soloSound = soloModeSound {
      return GlobalSettings.soloToken(forFileName: soloSound.fileName)
    }
    if isQuickMix {
      return GlobalSettings.quickMixToken
    }
    if let preset = PresetManager.shared.currentPreset {
      return preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
    }
    return nil
  }

  /// Resolves one `starredItems` token to widget-display info, mirroring the
  /// token resolution CarPlay's `HomeListTemplate`/`PresetListTemplate` use.
  ///
  /// Non-preset items (no accent of their own) use the app's real
  /// `customAccentColor` here, the same fallback `publishWidgetSnapshot`
  /// resolves for the live playback accent — not a bare `nil`, which would
  /// leave the *widget's own* generic `Color("AccentColor")` asset as the
  /// fallback instead and read as a different, wrong color from what
  /// `NowPlayingWidget` shows for that same sound while it's playing.
  func widgetFavorite(forToken token: String) -> WidgetFavorite? {
    if token == GlobalSettings.allSoundsToken {
      return WidgetFavorite(
        token: token,
        displayName: String(localized: "All Blankie Sounds"),
        systemIconName: "square.grid.2x2",
        thumbnailKey: nil,
        accentColorName: GlobalSettings.shared.customAccentColor?.toString,
        subtitle: nil
      )
    }
    if token == GlobalSettings.quickMixToken {
      return WidgetFavorite(
        token: token,
        displayName: String(localized: "Quick Mix"),
        systemIconName: "shuffle",
        thumbnailKey: nil,
        accentColorName: GlobalSettings.shared.customAccentColor?.toString,
        subtitle: nil
      )
    }
    if let fileName = GlobalSettings.soloFileName(fromToken: token) {
      guard let soloSound = sound(fileName: fileName) else { return nil }
      return WidgetFavorite(
        token: token,
        displayName: soloSound.localizedTitle,
        systemIconName: soloSound.systemIconName,
        thumbnailKey: nil,
        accentColorName: GlobalSettings.shared.customAccentColor?.toString,
        subtitle: soloSound.isCustom ? soloSound.creditedAuthor : nil
      )
    }
    guard let presetID = UUID(uuidString: token),
      let preset = PresetManager.shared.presets.first(where: { $0.id == presetID })
    else { return nil }
    return WidgetFavorite(
      token: token,
      displayName: preset.displayName,
      systemIconName: "square.stack.3d.up.fill",
      thumbnailKey: "preset_thumb_\(preset.id.uuidString)",
      accentColorName: preset.accentColorName,
      subtitle: presetSubtitle(for: preset)
    )
  }
}
