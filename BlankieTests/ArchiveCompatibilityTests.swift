//
//  ArchiveCompatibilityTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The version gate decides whether an imported `.blankie` is accepted. It must
//  compare versions numerically (not lexicographically) so "10.0.0" > "2.0.0".
//

import Foundation
import Testing

@testable import Blankie

@Suite struct ArchiveCompatibilityTests {

  private func compatibility(minimum: String) throws -> ArchiveCompatibility {
    let json = #"{"minimumBlankieVersion":"\#(minimum)","requiredFeatures":[]}"#
    return try JSONDecoder().decode(ArchiveCompatibility.self, from: Data(json.utf8))
  }

  /// A manifest survives an encode/decode round-trip with its derived fields.
  @Test func manifestRoundTripPreservesFields() throws {
    let manifest = ArchiveManifest(blankieVersion: "2.3.1")
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(ArchiveManifest.self, from: data)

    #expect(decoded.version == "1.0")
    #expect(decoded.blankieVersion == "2.3.1")
    #expect(decoded.compatibility.minimumBlankieVersion == "2.0.0")
    #expect(decoded.compatibility.requiredFeatures.isEmpty)
  }

  /// The default minimum for newly created archives is the v2 floor.
  @Test func defaultMinimumIsV2() {
    #expect(ArchiveCompatibility().minimumBlankieVersion == "2.0.0")
  }

  /// Equal-or-newer current versions are compatible; older ones are not.
  @Test func compatibilityHonorsMinimum() throws {
    let gate = try compatibility(minimum: "2.0.0")
    #expect(gate.isCompatible(with: "2.0.0"))
    #expect(gate.isCompatible(with: "2.0.1"))
    #expect(gate.isCompatible(with: "3.0.0"))
    #expect(!gate.isCompatible(with: "1.9.0"))
    #expect(!gate.isCompatible(with: "1.0.0"))
  }

  /// The numeric-comparison guard: lexicographically "10" < "2", but a build at
  /// 10.x must still satisfy a 9.x minimum.
  @Test func compatibilityIsNumericNotLexicographic() throws {
    let gate = try compatibility(minimum: "9.0.0")
    #expect(gate.isCompatible(with: "10.0.0"))
    #expect(gate.isCompatible(with: "9.0.0"))
    #expect(!gate.isCompatible(with: "8.9.0"))

    // Multi-digit minor segments order correctly too.
    let minorGate = try compatibility(minimum: "1.9.0")
    #expect(minorGate.isCompatible(with: "1.10.0"))
  }
}
