//
//  SoundMetadataModelTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The shipped sound catalog and credit/license value types. Decoding the
//  bundled sounds.json is the empty-grid-on-launch canary; License/Mood drift
//  would mis-tag or mis-link every sound's credits.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct SoundMetadataModelTests {

  /// The bundled catalog decodes and still contains the full built-in library.
  @Test func shippedSoundsJSONDecodes() throws {
    let url = try #require(Bundle.main.url(forResource: "sounds", withExtension: "json"))
    let container = try JSONDecoder().decode(SoundsContainer.self, from: Data(contentsOf: url))
    #expect(container.sounds.count >= 20, "the built-in library should be fully present")
    #expect(container.sounds.contains { $0.fileName == "rain" })
    // Every entry has the fields the grid needs.
    for sound in container.sounds {
      #expect(!sound.title.isEmpty)
      #expect(!sound.fileName.isEmpty)
      #expect(!sound.systemIconName.isEmpty)
    }
  }

  @Test func soundMoodHasThreeCasesAndRoundTrips() throws {
    #expect(SoundMood.allCases.count == 3)
    for mood in SoundMood.allCases {
      #expect(!mood.displayName.isEmpty)
      #expect(!mood.icon.isEmpty)
      let data = try JSONEncoder().encode(mood)
      #expect(try JSONDecoder().decode(SoundMood.self, from: data) == mood)
    }
  }

  @Test func licenseLinksAndRoundTrips() {
    #expect(License(rawValue: "cc0") == .cc0)
    #expect(License(rawValue: "nope") == nil)
    #expect(License.ccBy4.linkText == "CC BY 4.0")
    // Creative Commons licenses link out; bespoke ones don't.
    #expect(License.cc0.url != nil)
    #expect(License.ccBy3.url != nil)
    #expect(License.custom.url == nil)
    #expect(License.allRightsReserved.url == nil)
  }

  @Test func soundCreditAttribution() {
    let credit = SoundCredit(
      name: "Rain", soundName: "Heavy Rain", author: "Jane Doe", license: .ccBy4, soundUrl: nil)
    #expect(credit.attributionText == "\"Heavy Rain\" by Jane Doe")
  }
}
