//
//  PresetFactory.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Builds `Preset` / `PresetState` values for tests. Every optional defaults to
//  a NON-default value so a round-trip or remap that silently drops a field is
//  detectable. Override any argument per test.
//

import Foundation

@testable import Blankie

enum PresetFactory {
  static func makeState(
    fileName: String = "rain",
    isSelected: Bool = true,
    volume: Float = 0.5
  ) -> PresetState {
    PresetState(fileName: fileName, isSelected: isSelected, volume: volume)
  }

  static func makePreset(
    id: UUID = UUID(),
    name: String = "Test Preset",
    soundStates: [PresetState] = [
      PresetState(fileName: "rain", isSelected: true, volume: 0.5),
      PresetState(fileName: "waves", isSelected: false, volume: 0.8),
    ],
    isDefault: Bool = false,
    createdVersion: String? = "1.0.0",
    lastModifiedVersion: String? = "2.0.0",
    soundOrder: [String]? = ["rain", "waves"],
    creatorName: String? = "Tester",
    artworkId: UUID? = nil,
    animatedArtwork: AnimatedArtworkRef? = nil,
    staticArtworkPath: String? = nil,
    order: Int? = 3,
    isImported: Bool? = false,
    originalId: UUID? = nil,
    moods: [SoundMood]? = nil,
    accentColorName: String? = "blue",
    viewMode: PresetViewMode? = .list,
    backgroundBlurRadius: Double? = 12.0
  ) -> Preset {
    Preset(
      id: id,
      name: name,
      soundStates: soundStates,
      isDefault: isDefault,
      createdVersion: createdVersion,
      lastModifiedVersion: lastModifiedVersion,
      soundOrder: soundOrder,
      creatorName: creatorName,
      artworkId: artworkId,
      animatedArtwork: animatedArtwork,
      staticArtworkPath: staticArtworkPath,
      order: order,
      isImported: isImported,
      originalId: originalId,
      moods: moods,
      accentColorName: accentColorName,
      viewMode: viewMode,
      backgroundBlurRadius: backgroundBlurRadius
    )
  }
}
