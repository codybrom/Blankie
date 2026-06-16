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
}
