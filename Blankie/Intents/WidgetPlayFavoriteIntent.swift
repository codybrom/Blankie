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

  /// Set when the widget drew this item as playing, so the tap only pauses.
  @Parameter(title: "Pause", default: false)
  var pauses: Bool

  init() {}

  /// Explicit init: the synthesized memberwise init for a `@Parameter`
  /// property doesn't accept its plain wrapped-value type here.
  init(favoriteToken: String, pauses: Bool = false) {
    self.favoriteToken = favoriteToken
    self.pauses = pauses
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared

    // Follows the glyph the widget drew rather than toggling, so a Pause left
    // showing after the app was killed can't start audio in the cold app.
    if pauses {
      audio.setGlobalPlaybackState(false)
      return .result()
    }
    if favoriteToken == audio.currentFavoriteToken {
      audio.setGlobalPlaybackState(true)
      return .result()
    }

    // Resolve the token first so a stale tile throws without touching what's
    // playing. `playPreset` leaves single sound and Quick Mix itself.
    switch PlayableItem(token: favoriteToken) {
    case .allSounds:
      if let defaultPreset = PresetManager.shared.presets.first(where: { $0.isDefault }) {
        try PresetManager.shared.playPreset(defaultPreset)
      }
      return .result()
    case .quickMix:
      // Entering Quick Mix or single sound leaves the other mode itself.
      audio.enterQuickMix()
      return .result()
    case .single(let fileName):
      guard let singleSound = audio.sound(fileName: fileName) else {
        throw BlankieIntentError.soundNotFound
      }
      audio.enterSingleSound(for: singleSound)
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
