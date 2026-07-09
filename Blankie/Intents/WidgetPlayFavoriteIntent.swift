//
//  WidgetPlayFavoriteIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents

/// Plays a favorited item from a widget/Control tap. Takes a plain
/// `starredItems` token rather than an entity type (unlike `PlayPresetIntent`)
/// so the widget extension never needs to query `PresetManager`/`AudioManager`
/// just to resolve a parameter — the token is already known from the cached
/// `WidgetSnapshot` the tile/control was built from.
struct WidgetPlayFavoriteIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Play Favorite" }
  static var description: IntentDescription {
    IntentDescription("Plays a favorited preset, Quick Mix, or sound from Blankie.")
  }

  @Parameter(title: "Favorite")
  var favoriteToken: String

  init() {}

  /// Explicit init: the synthesized memberwise init for a `@Parameter`
  /// property doesn't accept its plain wrapped-value type here.
  init(favoriteToken: String) {
    self.favoriteToken = favoriteToken
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    // A not-yet-configured Control Center control passes an empty token. No-op
    // rather than falling through to the generic "preset not found" error.
    guard !favoriteToken.isEmpty else { return .result() }

    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared

    // Tapping the tile that's already active reads as "pause this", not
    // "restart this" — matches the tile's own play/pause glyph in the widget.
    if favoriteToken == audio.currentFavoriteToken {
      audio.togglePlayback()
      return .result()
    }

    // `PresetManager.executePresetApplication` no-ops sound-state application
    // while a solo sound is active (originally for the narrow launch-restore
    // case, where a preset is recorded as current but shouldn't disturb an
    // already-playing solo sound) — that guard silently blocks every other
    // preset tap while solo is active too, since it can't tell them apart.
    // Exiting solo explicitly first, before applying, sidesteps that guard.
    // `applyPreset` never exits Quick Mix on its own; leaving both transient
    // modes here (via the shared helper) also fixes the bug where `isQuickMix`
    // stayed `true` after a widget preset tap, so a later Quick Mix tap toggled
    // on top of the preset instead of entering fresh.
    audio.leaveTransientModes()

    switch PlayableItem(token: favoriteToken) {
    case .allSounds:
      if let defaultPreset = PresetManager.shared.presets.first(where: { $0.isDefault }) {
        try PresetManager.shared.applyPreset(defaultPreset)
        audio.setGlobalPlaybackState(true)
      }
      return .result()
    case .quickMix:
      audio.enterQuickMix()
      return .result()
    case .solo(let fileName):
      guard let soloSound = audio.sound(fileName: fileName) else {
        throw BlankieIntentError.presetNotFound
      }
      audio.enterSoloMode(for: soloSound)
      return .result()
    case .preset(let id):
      guard let preset = PresetManager.shared.presets.first(where: { $0.id == id }) else {
        throw BlankieIntentError.presetNotFound
      }
      try PresetManager.shared.applyPreset(preset)
      audio.setGlobalPlaybackState(true)
      return .result()
    case nil:
      throw BlankieIntentError.presetNotFound
    }
  }
}
