//
//  WidgetPlayFavoriteIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents

/// Plays a favorited item from a widget tap. Takes a plain `starredItems` token
/// from the cached `WidgetSnapshot`, so the widget never queries the managers.
struct WidgetPlayFavoriteIntent: AppIntent, AudioPlaybackIntent {
  static var isDiscoverable: Bool { false }

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
    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared

    // Tapping the active tile toggles playback, matching its play/pause glyph.
    if favoriteToken == audio.currentFavoriteToken {
      audio.togglePlayback()
      return .result()
    }

    // Resolve the token first so a stale tile throws without touching what's
    // playing. `playPreset` leaves solo and Quick Mix itself.
    switch PlayableItem(token: favoriteToken) {
    case .allSounds:
      if let defaultPreset = PresetManager.shared.presets.first(where: { $0.isDefault }) {
        try PresetManager.shared.playPreset(defaultPreset)
      }
      return .result()
    case .quickMix:
      // Entering Quick Mix or solo leaves the other mode itself.
      audio.enterQuickMix()
      return .result()
    case .solo(let fileName):
      guard let soloSound = audio.sound(fileName: fileName) else {
        throw BlankieIntentError.soundNotFound
      }
      audio.enterSoloMode(for: soloSound)
      return .result()
    case .preset(let id):
      guard let preset = PresetManager.shared.presets.first(where: { $0.id == id }) else {
        throw BlankieIntentError.presetNotFound
      }
      try PresetManager.shared.playPreset(preset)
      return .result()
    case nil:
      throw BlankieIntentError.presetNotFound
    }
  }
}
