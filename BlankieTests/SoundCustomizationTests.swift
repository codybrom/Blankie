//
//  SoundCustomizationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Per-built-in-sound overrides. A Codable round-trip that drops a field
//  silently resets a user's per-sound setting; `hasCustomizations` decides
//  whether a row is kept or pruned.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct SoundCustomizationTests {

  @Test func freshCustomizationHasNoOverrides() {
    let c = SoundCustomization(fileName: "rain")
    #expect(c.customTitle == nil)
    #expect(c.customIconName == nil)
    #expect(c.loopSound == nil)
    #expect(!c.hasCustomizations)
  }

  @Test func effectiveTitleAndIconFallBackToOriginal() {
    let bare = SoundCustomization(fileName: "rain")
    #expect(bare.effectiveTitle(originalTitle: "Rain") == "Rain")
    #expect(bare.effectiveIconName(originalIconName: "cloud") == "cloud")

    let custom = SoundCustomization(
      fileName: "rain", customTitle: "Storm", customIconName: "bolt")
    #expect(custom.effectiveTitle(originalTitle: "Rain") == "Storm")
    #expect(custom.effectiveIconName(originalIconName: "cloud") == "bolt")
  }

  @Test func hasCustomizationsTracksAnyField() {
    #expect(SoundCustomization(fileName: "x", loopSound: false).hasCustomizations)
    #expect(SoundCustomization(fileName: "x", isMusic: true).hasCustomizations)
    #expect(SoundCustomization(fileName: "x", volumeAdjustment: 1.5).hasCustomizations)
    #expect(!SoundCustomization(fileName: "x").hasCustomizations)
  }

  /// Every field survives a JSON round-trip; a regression here silently resets
  /// per-sound settings on the next launch.
  @Test func codableRoundTripPreservesEveryField() throws {
    let original = SoundCustomization(
      fileName: "rain",
      customTitle: "Storm",
      customIconName: "bolt",
      randomizeStartPosition: true,
      normalizeAudio: false,
      volumeAdjustment: 1.25,
      loopSound: false,
      fadeSound: false,
      isPresetUseOnly: true,
      isMusic: true)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SoundCustomization.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.fileName == "rain")
    #expect(decoded.customTitle == "Storm")
    #expect(decoded.customIconName == "bolt")
    #expect(decoded.randomizeStartPosition == true)
    #expect(decoded.normalizeAudio == false)
    #expect(decoded.volumeAdjustment == 1.25)
    #expect(decoded.loopSound == false)
    #expect(decoded.fadeSound == false)
    #expect(decoded.isPresetUseOnly == true)
    #expect(decoded.isMusic == true)
  }
}
