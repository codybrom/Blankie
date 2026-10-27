//
//  PresetImporterRemappingTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Imported custom sounds get fresh IDs, so the preset's sound-state references are rewritten.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PresetImporterRemappingTests {

  @Test func remapsCustomSoundStates() {
    let oldId = UUID()
    let newId = UUID()
    let custom = PresetState(fileName: oldId.uuidString, isSelected: true, volume: 0.4)
    let preset = PresetFactory.makePreset(soundStates: [custom])

    let result = PresetImporter.shared.updatePresetSoundStates(preset, with: [oldId: newId])

    let state = try! #require(result.soundStates.first)
    #expect(state.fileName == newId.uuidString)
    #expect(state.isSelected)
    #expect(isClose(state.volume, 0.4))
  }

  @Test func leavesUnmappedAndBuiltInStatesUntouched() {
    let mappedOld = UUID()
    let mappedNew = UUID()
    let unmapped = UUID()
    let builtIn = PresetState(fileName: "rain", isSelected: false, volume: 0.8)
    let unmappedState = PresetState(fileName: unmapped.uuidString, isSelected: true, volume: 0.3)
    let mappedState = PresetState(fileName: mappedOld.uuidString, isSelected: true, volume: 0.6)
    let preset = PresetFactory.makePreset(soundStates: [builtIn, unmappedState, mappedState])

    let result = PresetImporter.shared.updatePresetSoundStates(
      preset, with: [mappedOld: mappedNew])

    #expect(result.soundStates[0].fileName == "rain")
    #expect(result.soundStates[1].fileName == unmapped.uuidString)
    #expect(result.soundStates[2].fileName == mappedNew.uuidString)
  }

  @Test func emptyMappingIsNoOp() {
    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: UUID().uuidString, isSelected: true, volume: 0.5)])
    let result = PresetImporter.shared.updatePresetSoundStates(preset, with: [:])
    #expect(result.soundStates == preset.soundStates)
  }

  /// The original ID is kept for duplicate detection. An imported copy is never the default.
  @Test func createNewInstanceReIDsAndMarksImported() {
    let original = PresetFactory.makePreset(isDefault: true, isImported: false)

    let result = PresetImporter.shared.createNewPresetInstance(from: original)

    #expect(result.id != original.id)
    #expect(result.isDefault == false)
    #expect(result.isImported == true)
    #expect(result.originalId == original.id)
    #expect(result.lastModifiedVersion != nil)
  }

  @Test func createNewInstanceCarriesThemeAndContent() {
    let original = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: "rain", isSelected: true, volume: 0.7)],
      soundOrder: ["rain", "fire"],
      moods: nil,
      accentColorName: "purple",
      viewMode: .grid,
      backgroundBlurRadius: 8.0)

    let result = PresetImporter.shared.createNewPresetInstance(from: original)

    #expect(result.name == original.name)
    #expect(result.soundStates == original.soundStates)
    #expect(result.soundOrder == original.soundOrder)
    #expect(result.accentColorName == "purple")
    #expect(result.viewMode == .grid)
    #expect(result.backgroundBlurRadius == 8.0)
    #expect(result.creatorName == original.creatorName)
  }
}
