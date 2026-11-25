//
//  SoundEqualizerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 11/24/26.
//
//  The per-sound equalizer: cleaning saved curves, the loudness trim, the bands it sets on an EQ
//  unit, the preset curves and how a curve is saved with a sound's customization.
//

import AVFoundation
import Foundation
import Testing

@testable import Blankie

@Suite @MainActor struct SoundEqualizerTests {
  nonisolated private static let fileName = "test-equalizer-sound"

  // MARK: - Cleaning curves

  @Test func flatAndMalformedCurvesCleanToNil() {
    #expect(SoundEqualizer.sanitized(nil) == nil)
    #expect(SoundEqualizer.sanitized(SoundEqualizer.flat) == nil)
    #expect(SoundEqualizer.sanitized([3, 3, 3]) == nil)
    #expect(SoundEqualizer.sanitized([0, 0, 0, .nan, 0, 0, 0]) == nil)
    #expect(SoundEqualizer.sanitized([0, 0, 0, .infinity, 0, 0, 0]) == nil)
  }

  @Test func curvesClampToTheBandRange() {
    let cleaned = SoundEqualizer.sanitized([100, -100, 6, 0, 0, 0, 0])
    #expect(cleaned == [18, -18, 6, 0, 0, 0, 0])
  }

  // MARK: - Loudness trim

  @Test func trimOffsetsTheAverageGain() {
    #expect(SoundEqualizer.loudnessTrimDB(for: SoundEqualizer.flat) == 0)
    #expect(SoundEqualizer.loudnessTrimDB(for: GraphicEQPreset.increaseBass.gains) < 0)
    #expect(SoundEqualizer.loudnessTrimDB(for: GraphicEQPreset.reduceBass.gains) > 0)
  }

  @Test func trimStaysInsideItsLimits() {
    let allUp = [Float](repeating: 18, count: 7)
    let allDown = [Float](repeating: -18, count: 7)
    #expect(SoundEqualizer.loudnessTrimDB(for: allUp) == -9)
    #expect(SoundEqualizer.loudnessTrimDB(for: allDown) == 6)
  }

  // MARK: - EQ unit

  @Test func newUnitHasOneBypassedBandPerFrequency() {
    let unit = SoundEqualizer.makeUnit()
    #expect(unit.bands.count == SoundEqualizer.frequencies.count)
    #expect(unit.bands.allSatisfy { $0.bypass })
    #expect(unit.globalGain == 0)
  }

  @Test func applySetsOnlyTheBandsThatMove() {
    let unit = SoundEqualizer.makeUnit()
    let trim = SoundEqualizer.apply([0, 0, 6, 0, 0, -12, 0], to: unit)

    #expect(unit.bands[2].bypass == false)
    #expect(unit.bands[2].gain == 6)
    #expect(unit.bands[2].frequency == 400)
    #expect(unit.bands[2].filterType == .parametric)
    #expect(unit.bands[5].bypass == false)
    #expect(unit.bands[5].gain == -12)
    #expect(unit.bands[5].frequency == 6_000)
    for index in [0, 1, 3, 4, 6] {
      #expect(unit.bands[index].bypass)
    }
    #expect(trim == SoundEqualizer.loudnessTrimDB(for: [0, 0, 6, 0, 0, -12, 0]))
  }

  @Test func applyingFlatBypassesEveryBandAgain() {
    let unit = SoundEqualizer.makeUnit()
    _ = SoundEqualizer.apply(GraphicEQPreset.oldRadio.gains, to: unit)
    let trim = SoundEqualizer.apply(SoundEqualizer.flat, to: unit)

    #expect(unit.bands.allSatisfy { $0.bypass })
    #expect(trim == 0)
  }

  @Test func malformedGainsApplyAsFlat() {
    let unit = SoundEqualizer.makeUnit()
    let trim = SoundEqualizer.apply([12, 12], to: unit)

    #expect(unit.bands.allSatisfy { $0.bypass })
    #expect(trim == 0)
  }

  // MARK: - Presets

  @Test func everyPresetFitsTheBands() {
    for preset in GraphicEQPreset.allCases {
      #expect(preset.gains.count == SoundEqualizer.frequencies.count)
      #expect(preset.gains.allSatisfy { abs($0) <= SoundEqualizer.rangeDB })
    }
  }

  @Test func presetCurvesAreDistinctAndOnlyFlatIsFlat() {
    let curves = GraphicEQPreset.allCases.map(\.gains)
    #expect(Set(curves).count == curves.count)
    #expect(GraphicEQPreset.flat.gains == SoundEqualizer.flat)
    for preset in GraphicEQPreset.allCases where preset != .flat {
      #expect(SoundEqualizer.sanitized(preset.gains) == preset.gains)
    }
  }

  @Test func curvesMatchTheirPresetAndHandEditsMatchNone() {
    for preset in GraphicEQPreset.allCases {
      #expect(GraphicEQPreset.matching(preset.gains) == preset)
    }
    var edited = GraphicEQPreset.increaseBass.gains
    edited[6] = 4
    #expect(GraphicEQPreset.matching(edited) == nil)
    #expect(GraphicEQPreset.name(for: edited) != GraphicEQPreset.increaseBass.name)
  }

  // MARK: - Saving

  @Test func customizationRoundTripsTheCurve() throws {
    let original = SoundCustomization(
      fileName: "rain", equalizerGains: GraphicEQPreset.nextRoom.gains)
    #expect(original.hasCustomizations)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SoundCustomization.self, from: data)
    #expect(decoded.equalizerGains == GraphicEQPreset.nextRoom.gains)
  }

  /// Customizations saved before the equalizer existed have no such key.
  @Test func customizationWithoutACurveStillDecodes() throws {
    let json = """
      {"id":"8B1F6E0A-52D3-4F0B-9B0E-3B6C1C2D4E5F","fileName":"rain","loopSound":false}
      """
    let decoded = try JSONDecoder().decode(SoundCustomization.self, from: Data(json.utf8))
    #expect(decoded.equalizerGains == nil)
    #expect(decoded.loopSound == false)
  }

  @Test func managerSavesACurveAndAFlatOneClearsIt() {
    let manager = SoundCustomizationManager.shared
    defer { manager.removeCustomization(for: Self.fileName) }

    manager.setEqualizerGains([100, 0, 0, 0, 0, 0, -6], for: Self.fileName)
    #expect(
      manager.getCustomization(for: Self.fileName)?.equalizerGains == [18, 0, 0, 0, 0, 0, -6])

    manager.setEqualizerGains(SoundEqualizer.flat, for: Self.fileName)
    #expect(manager.getCustomization(for: Self.fileName) == nil)
  }

  @Test func soundReadsAndWritesItsSavedCurve() {
    defer { SoundCustomizationManager.shared.removeCustomization(for: Self.fileName) }
    let sound = TestSound(fileName: Self.fileName)
    #expect(sound.equalizerGains == SoundEqualizer.flat)

    sound.setEqualizer(gains: GraphicEQPreset.reduceTreble.gains)
    #expect(sound.equalizerGains == GraphicEQPreset.reduceTreble.gains)

    sound.setEqualizer(gains: SoundEqualizer.flat)
    #expect(sound.equalizerGains == SoundEqualizer.flat)
  }
}
