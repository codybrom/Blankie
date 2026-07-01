//
//  SoundEntity.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// App Intents-facing wrapper around `Sound`, keyed by the sound's stable
/// `fileName` (not its `UUID`, which is re-minted every launch).
struct SoundEntity: AppEntity {
  let id: String
  var title: String
  var systemIconName: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Sound")
  }

  static var defaultQuery: SoundEntityQuery { SoundEntityQuery() }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", image: .init(systemName: systemIconName))
  }

  // AppEntity requires Sendable, which opts this struct out of the project's
  // default main-actor isolation — so unlike a plain `nonisolated struct` model
  // (e.g. `Preset`), reading `Sound`'s main-actor-isolated computed properties
  // here needs an explicit annotation.
  @MainActor
  init(sound: Sound) {
    id = sound.fileName
    title = sound.localizedTitle
    systemIconName = sound.systemIconName
  }
}

struct SoundEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
  @MainActor
  func entities(for identifiers: [SoundEntity.ID]) async throws -> [SoundEntity] {
    let sounds = AudioManager.shared.sounds
    return identifiers.compactMap { fileName in
      sounds.first { $0.fileName == fileName }.map(SoundEntity.init)
    }
  }

  @MainActor
  func entities(matching string: String) async throws -> [SoundEntity] {
    AudioManager.shared.sounds
      .filter { !$0.isPresetUseOnly && $0.localizedTitle.localizedCaseInsensitiveContains(string) }
      .map(SoundEntity.init)
  }

  @MainActor
  func suggestedEntities() async throws -> [SoundEntity] {
    let selected = AudioManager.shared.sounds.filter(\.isSelected)
    let source =
      selected.isEmpty ? AudioManager.shared.sounds.filter { !$0.isPresetUseOnly } : selected
    return source.map(SoundEntity.init)
  }

  @MainActor
  func allEntities() async throws -> [SoundEntity] {
    AudioManager.shared.sounds.filter { !$0.isPresetUseOnly }.map(SoundEntity.init)
  }
}
