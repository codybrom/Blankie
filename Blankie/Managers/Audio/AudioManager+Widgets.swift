//
//  AudioManager+Widgets.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import Foundation
import SwiftUI

extension AudioManager {
  /// Publish the requested playback state before an intent returns and WidgetKit
  /// reloads. System Now Playing backends may wait for a debounce or fade-out;
  /// the widgets have no such engine requirement. Use the same display rules,
  /// resolving all fields together so a new mix cannot inherit the old title.
  @MainActor
  func publishCurrentWidgetSnapshot() {
    let preset = PresetManager.shared.currentPreset
    let overridden = soloModeSound != nil || isQuickMix
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

  /// Build the shared snapshot for an immediate playback transition or a
  /// backend metadata refresh. WidgetStateStore deduplicates identical writes.
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
        // glyph (matching its sidebar row), not whichever individual
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
      favorites: widgetFavorites(),
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
      favorites: widgetFavorites(),
      quickMixSounds: widgetQuickMixSounds(),
      pinnableItems: widgetPinnableItems(),
      defaultAccentColorName: GlobalSettings.shared.customAccentColor?.toString
    )
    WidgetStateStore.publish(snapshot)
  }

  /// The starred items for the Favorites widget. Quick Mix is left out, as in
  /// CarPlay: a tile can't pick its sounds, so entering it would only go silent.
  private func widgetFavorites() -> [WidgetFavorite] {
    GlobalSettings.shared.starredItems
      .filter { $0 != GlobalSettings.quickMixToken }
      .compactMap(widgetFavorite(forToken:))
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
        isSelected: isQuickMix && quickMixSound.isSelected,
        volume: isQuickMix ? quickMixSound.volume : 0.8
      )
    }
  }

  /// Every preset plus every solo-able sound, for the Pinned Sound widget's
  /// configuration picker — unlike `favorites`, this isn't filtered by
  /// `starredItems`, since pinning one specific thing to the Home Screen
  /// shouldn't require starring it first. Mirrors CarPlay's
  /// `SoundsListTemplate` solo-eligibility filter (`!isPresetUseOnly`).
  /// Resolved through `widgetFavorite(forToken:)` so a pinned item and its
  /// Favorites tile share one identity.
  func widgetPinnableItems() -> [WidgetFavorite] {
    let presetTokens = PresetManager.shared.presets.map { preset in
      preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
    }
    let soundTokens = sounds.filter { !$0.isPresetUseOnly }.map { sound in
      GlobalSettings.soloToken(forFileName: sound.fileName)
    }
    return (presetTokens + soundTokens).compactMap(widgetFavorite(forToken:))
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

  /// The `starredItems` token matching what's currently active, if any — the
  /// persisted form of `activeItem`, which also drives `themingPreset` so the
  /// two agree on what's "in charge" of the mixer (solo, then Quick Mix, then
  /// preset).
  @MainActor
  var currentFavoriteToken: String? {
    activeItem?.token
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
