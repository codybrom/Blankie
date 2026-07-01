//
//  PresetEntity.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// App Intents-facing wrapper around `Preset`, so Siri/Shortcuts can pick a
/// preset by name without exposing the full model (artwork, sound states, etc).
struct PresetEntity: AppEntity {
  let id: UUID
  var name: String
  var isDefault: Bool

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Preset")
  }

  static var defaultQuery: PresetEntityQuery { PresetEntityQuery() }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      image: .init(systemName: isDefault ? "square.grid.2x2" : "square.stack.3d.up.fill")
    )
  }

  init(preset: Preset) {
    id = preset.id
    name = preset.displayName
    isDefault = preset.isDefault
  }
}

struct PresetEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
  @MainActor
  func entities(for identifiers: [PresetEntity.ID]) async throws -> [PresetEntity] {
    let presets = PresetManager.shared.presets
    return identifiers.compactMap { id in
      presets.first { $0.id == id }.map(PresetEntity.init)
    }
  }

  @MainActor
  func entities(matching string: String) async throws -> [PresetEntity] {
    PresetManager.shared.presets
      .filter { $0.displayName.localizedCaseInsensitiveContains(string) }
      .map(PresetEntity.init)
  }

  @MainActor
  func suggestedEntities() async throws -> [PresetEntity] {
    PresetManager.shared.getRecentPresets().map(PresetEntity.init)
  }

  @MainActor
  func allEntities() async throws -> [PresetEntity] {
    PresetManager.shared.presets.map(PresetEntity.init)
  }
}
