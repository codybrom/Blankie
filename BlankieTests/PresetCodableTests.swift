//
//  PresetCodableTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Full-fidelity Preset round-trip. Export, import, and the preset store all
//  serialize the whole Preset; a CodingKeys or optionality change that drops
//  artwork / moods / order / view mode silently loses user data on every
//  save/import/export. PresetFactory seeds non-default values so a dropped field
//  is detectable.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PresetCodableTests {

  @Test func encodeDecodePreservesAllFields() throws {
    let artwork = AnimatedArtworkRef(
      source: .custom, loopPath: "loop.mov", previewPath: "preview.png",
      squarePreviewPath: "square.png", preferredAspect: "3:4", bundledIdentifier: "rainforest")
    let original = PresetFactory.makePreset(
      name: "Full Fidelity",
      artworkId: UUID(),
      animatedArtwork: artwork,
      staticArtworkPath: "static/art.png",
      moods: [.sleep, .focus],
      accentColorName: "teal",
      viewMode: .list,
      backgroundBlurRadius: 9.5)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Preset.self, from: data)

    // Field-by-field (not ==): Preset.== deliberately ignores originalId.
    #expect(decoded.id == original.id)
    #expect(decoded.name == original.name)
    #expect(decoded.soundStates == original.soundStates)
    #expect(decoded.soundOrder == original.soundOrder)
    #expect(decoded.isDefault == original.isDefault)
    #expect(decoded.createdVersion == original.createdVersion)
    #expect(decoded.lastModifiedVersion == original.lastModifiedVersion)
    #expect(decoded.creatorName == original.creatorName)
    #expect(decoded.artworkId == original.artworkId)
    #expect(decoded.animatedArtwork == original.animatedArtwork)
    #expect(decoded.staticArtworkPath == original.staticArtworkPath)
    #expect(decoded.order == original.order)
    #expect(decoded.isImported == original.isImported)
    #expect(decoded.moods == original.moods)
    #expect(decoded.accentColorName == original.accentColorName)
    #expect(decoded.viewMode == original.viewMode)
    #expect(decoded.backgroundBlurRadius == original.backgroundBlurRadius)
  }
}
