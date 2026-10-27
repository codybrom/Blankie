//
//  PresetEntity.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// App Intents wrapper around `Preset` for Siri, Shortcuts and Spotlight. The
/// default index attributes come from `displayRepresentation` (title and icon).
struct PresetEntity: AppEntity, IndexedEntity {
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
    await AppSetup.ensureManagersReadyForIntents()
    let presets = PresetManager.shared.presets
    return identifiers.compactMap { id in
      presets.first { $0.id == id }.map(PresetEntity.init)
    }
  }

  @MainActor
  func entities(matching string: String) async throws -> [PresetEntity] {
    await AppSetup.ensureManagersReadyForIntents()
    return PresetManager.shared.presets
      .filter { $0.displayName.localizedCaseInsensitiveContains(string) }
      .map(PresetEntity.init)
  }

  /// Also the vocabulary for the parameterized Siri phrases
  /// (`updateAppShortcutParameters`), so every preset belongs here.
  @MainActor
  func suggestedEntities() async throws -> [PresetEntity] {
    try await allEntities()
  }

  @MainActor
  func allEntities() async throws -> [PresetEntity] {
    await AppSetup.ensureManagersReadyForIntents()
    return PresetManager.shared.presets.map(PresetEntity.init)
  }
}
