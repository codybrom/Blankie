//
//  AudioManager+Widgets.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import Foundation
import SwiftUI

extension AudioManager {
  /// Publishes the playback state before an intent returns and WidgetKit reloads,
  /// skipping the Now Playing debounce. Fields resolve together so a new mix can't
  /// keep the old title.
  @MainActor
  func publishCurrentWidgetSnapshot() {
    let preset = PresetManager.shared.currentPreset
    let overridden = singleSound != nil || isQuickMix
    let display = NowPlayingDisplay.getDisplayInfo(
      presetName: preset?.name, creatorName: preset?.creatorName, preset: preset)
    publishWidgetSnapshot(
      title: display.title,
      subtitle: NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: preset?.creatorName),
      isPlaying: isGloballyPlaying,
      thumbnailKey: overridden
        ? nil
        : preset.flatMap {
          $0.isDefault ? nil : "preset_thumb_\($0.id.uuidString)"
        },
      accentColorName: overridden ? nil : preset?.accentColorName)
  }

  /// WidgetStateStore deduplicates identical writes.
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
        // Quick Mix shows its shuffle glyph (as in the sidebar). Single sound keeps other
        // sounds selected, so it shows only the single sound's icon.
        soundSystemIconNames: {
          if let singleSound = singleSound { return [singleSound.systemIconName] }
          if isQuickMix { return ["shuffle"] }
          return playingSoundIcons(limit: 4)
        }(),
        thumbnailKey: thumbnailKey,
        activeToken: currentFavoriteToken,
        accentColorName: accentColorName ?? GlobalSettings.shared.customAccentColor?.toString
      ),
      favorites: widgetFavorites(),
      quickMixSounds: widgetQuickMixSounds(),
      pinnableItems: widgetPinnableItems(),
      defaultAccentColorName: GlobalSettings.shared.customAccentColor?.toString
    )
    WidgetStateStore.publish(snapshot)
  }

  /// Republishes favorites, Quick Mix, pinnable items and accent after a settings
  /// change, keeping the last-published playback state.
  @MainActor
  func republishWidgetCatalog() {
    let last = WidgetStateStore.current().playback
    // Recomputed so a global accent change shows at once: the active preset's
    // accent, else the app-wide custom accent.
    let presetAccent =
      singleSound == nil && !isQuickMix
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
      favorites: widgetFavorites(),
      quickMixSounds: widgetQuickMixSounds(),
      pinnableItems: widgetPinnableItems(),
      defaultAccentColorName: GlobalSettings.shared.customAccentColor?.toString
    )
    WidgetStateStore.publish(snapshot)
  }

  /// Starred items for the Favorites widget. Quick Mix is left out (as in CarPlay)
  /// because a tile can't pick its sounds.
  private func widgetFavorites() -> [WidgetFavorite] {
    GlobalSettings.shared.starredItems
      .filter { $0 != GlobalSettings.quickMixToken }
      .compactMap(widgetFavorite(forToken:))
  }

  /// Quick Mix sounds, marked selected only while Quick Mix is active (a preset
  /// can select the same sound).
  private func widgetQuickMixSounds() -> [WidgetQuickMixSound] {
    GlobalSettings.shared.quickMixSoundFileNames.compactMap { fileName in
      guard let quickMixSound = sound(fileName: fileName) else { return nil }
      return WidgetQuickMixSound(
        fileName: fileName,
        displayName: quickMixSound.localizedTitle,
        systemIconName: quickMixSound.systemIconName,
        isSelected: isQuickMix && quickMixSound.isSelected,
        volume: isQuickMix ? quickMixSound.volume : 0.8
      )
    }
  }

  /// Every preset and every sound that can play on its own for the Pinned Sound widget's picker,
  /// starred or not. Uses `widgetFavorite(forToken:)` so a pin matches its Favorites tile.
  func widgetPinnableItems() -> [WidgetFavorite] {
    let presetTokens = PresetManager.shared.presets.map { preset in
      preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
    }
    let soundTokens = sounds.filter { !$0.isPresetUseOnly }.map { sound in
      GlobalSettings.singleToken(forFileName: sound.fileName)
    }
    return (presetTokens + soundTokens).compactMap(widgetFavorite(forToken:))
  }

  /// Creator name, else a summary of the preset's stored sounds. Matches the Now
  /// Playing widget subtitle, so a pinned preset reads the same as when it plays.
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

  /// The `starredItems` token for `activeItem` (single sound, then Quick Mix, then preset).
  @MainActor
  var currentFavoriteToken: String? {
    activeItem?.token
  }

  /// Resolves a `starredItems` token to widget display info. Items without their
  /// own accent use the app's `customAccentColor`, as the playing widget does.
  func widgetFavorite(forToken token: String) -> WidgetFavorite? {
    guard let item = PlayableItem(token: token), let display = display(for: item) else {
      return nil
    }
    return WidgetFavorite(
      token: token,
      displayName: display.displayName,
      systemIconName: display.systemIconName,
      thumbnailKey: display.thumbnailKey,
      accentColorName: display.accentColorName,
      subtitle: display.subtitle
    )
  }
}
