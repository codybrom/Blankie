//
//  Controls.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct PlaybackValueProvider: ControlValueProvider {
  var previewValue: Bool { false }

  func currentValue() async throws -> Bool {
    WidgetStateStore.current().playback.isPlaying
  }
}

struct PlaybackControl: ControlWidget {
  static let kind = "com.codybrom.blankie.PlaybackControl"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind, provider: PlaybackValueProvider()) { isPlaying in
      ControlWidgetToggle(
        "Blankie",
        isOn: isPlaying,
        action: PlaybackToggleValueIntent()
      ) { isOn in
        Label(isOn ? "Playing" : "Paused", systemImage: isOn ? "pause.fill" : "play.fill")
      }
    }
    .displayName("Playback")
    .description("Play or pause Blankie.")
  }
}

/// Lightweight, snapshot-backed entity for the Favorite control's
/// configuration picker — reads the cached `WidgetSnapshot`, never
/// `PresetManager`/`AudioManager`, so choosing a favorite in Settings >
/// Control Center never touches the audio engine or SwiftData.
struct FavoriteControlEntity: AppEntity {
  let id: String
  var displayName: String
  var systemIconName: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Favorite")
  }

  static var defaultQuery: FavoriteControlEntityQuery { FavoriteControlEntityQuery() }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayName)", image: .init(systemName: systemIconName))
  }
}

struct FavoriteControlEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [String]) async throws -> [FavoriteControlEntity] {
    let favorites = WidgetStateStore.current().favorites
    return identifiers.compactMap { id in
      favorites.first { $0.token == id && $0.token != GlobalSettings.quickMixToken }.map {
        FavoriteControlEntity(
          id: $0.token, displayName: $0.displayName, systemIconName: $0.systemIconName)
      }
    }
  }

  // Quick Mix is a live, multi-sound mix, not a static thing to pin to one
  // slot — it gets its own dedicated widget (`QuickMixWidget`) instead,
  // mirroring how CarPlay's `QuickMixGridTemplate` handles it, rather than
  // appearing here as if it were a single preset/sound.
  @MainActor
  func suggestedEntities() async throws -> [FavoriteControlEntity] {
    WidgetStateStore.current().favorites
      .filter { $0.token != GlobalSettings.quickMixToken }
      .map {
        FavoriteControlEntity(
          id: $0.token, displayName: $0.displayName, systemIconName: $0.systemIconName)
      }
  }
}

struct FavoriteControlConfigurationIntent: ControlConfigurationIntent {
  static var title: LocalizedStringResource { "Choose Favorite" }

  @Parameter(title: "Favorite")
  var favorite: FavoriteControlEntity?
}

struct FavoriteControl: ControlWidget {
  static let kind = "com.codybrom.blankie.FavoriteControl"

  var body: some ControlWidgetConfiguration {
    AppIntentControlConfiguration(
      kind: Self.kind,
      intent: FavoriteControlConfigurationIntent.self
    ) { configuration in
      ControlWidgetButton(
        action: WidgetPlayFavoriteIntent(favoriteToken: configuration.favorite?.id ?? "")
      ) {
        Label(
          configuration.favorite?.displayName ?? "Choose a Favorite",
          systemImage: configuration.favorite?.systemIconName ?? "star"
        )
      }
    }
    .displayName("Play Favorite")
    .description("Play a favorited preset, Quick Mix, or sound from Blankie.")
  }
}
