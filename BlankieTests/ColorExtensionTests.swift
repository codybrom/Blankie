//
//  ColorExtensionTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Accent colors persist as strings. The name<->Color mapping must round-trip
//  or a saved accent silently reverts to the default.
//

import SwiftUI
import Testing

@testable import Blankie

@Suite struct ColorExtensionTests {

  @Test func stringRoundTripForNamedColors() {
    for name in [
      "red", "pink", "orange", "brown", "yellow", "green", "mint", "teal", "cyan",
      "blue", "indigo", "purple",
    ] {
      #expect(Color(fromString: name)?.toString == name, "round-trip failed for \(name)")
    }
  }

  @Test func unknownStringYieldsNil() {
    #expect(Color(fromString: "chartreuse") == nil)
    #expect(Color(fromString: "") == nil)
  }

  @Test func unmappedColorStringIsEmpty() {
    #expect(Color.clear.toString == "")
  }

  /// `.system` has no concrete color; all other accents resolve.
  @Test func systemAccentHasNoColor() {
    #expect(AccentColor.system.color == nil)
    #expect(AccentColor.blue.color != nil)
    #expect(!AccentColor.purple.name.isEmpty)
  }

  /// A label color is chosen for contrast: dark fills get white, light get black.
  @Test func contrastingLabelPicksReadableColor() {
    #expect(Color.white.contrastingLabel == Color.black)
    #expect(Color.black.contrastingLabel == Color.white)
  }

  /// Pins the 0.5 perceived-brightness cutoff — corner cases (white/black) alone
  /// don't catch a wrong threshold. A mid-light gray gets black, mid-dark white.
  @Test func contrastingLabelCutoffBoundary() {
    #expect(Color(white: 0.6).contrastingLabel == Color.black)
    #expect(Color(white: 0.4).contrastingLabel == Color.white)
  }

  /// Pins the luma weighting direction (green ≫ red ≫ blue): pure green is
  /// "light" (luma 0.587 → black label), pure blue is "dark" (0.114 → white).
  @Test func contrastingLabelUsesLumaWeights() {
    #expect(Color(red: 0, green: 1, blue: 0).contrastingLabel == Color.black)
    #expect(Color(red: 0, green: 0, blue: 1).contrastingLabel == Color.white)
    #expect(Color(red: 1, green: 0, blue: 0).contrastingLabel == Color.white)
  }
}
