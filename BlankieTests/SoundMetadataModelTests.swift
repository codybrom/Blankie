//
//  SoundMetadataModelTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The shipped sound catalog (sounds.json) and the credit, license and mood value types.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct SoundMetadataModelTests {

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

  /// The subtitle is the caption under the title in Now Playing and the sound pickers.
  @Test func everyBuiltInSoundHasSubtitle() throws {
    let url = try #require(Bundle.main.url(forResource: "sounds", withExtension: "json"))
    let container = try JSONDecoder().decode(SoundsContainer.self, from: Data(contentsOf: url))
    for sound in container.sounds {
      #expect(
        !(sound.subtitle ?? "").isEmpty,
        "built-in sound '\(sound.fileName)' is missing a subtitle")
    }
  }

  /// `localizedSubtitle` looks subtitles up with `NSLocalizedString`, so each one needs a
  /// catalog key or it shows in English.
  @Test func everySubtitleHasCatalogEntry() throws {
    let url = try #require(Bundle.main.url(forResource: "sounds", withExtension: "json"))
    let container = try JSONDecoder().decode(SoundsContainer.self, from: Data(contentsOf: url))
    let sentinel = "\u{1}__missing__"
    for sound in container.sounds {
      guard let subtitle = sound.subtitle, !subtitle.isEmpty else { continue }
      let resolved = Bundle.main.localizedString(forKey: subtitle, value: sentinel, table: nil)
      #expect(
        resolved != sentinel,
        "subtitle for '\(sound.fileName)' has no string-catalog key: \(subtitle)")
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
    // Creative Commons licenses link out, but bespoke ones don't.
    #expect(License.cc0.url != nil)
    #expect(License.ccBy3.url != nil)
    #expect(License.custom.url == nil)
    #expect(License.allRightsReserved.url == nil)
  }

  @Test func soundCreditAttribution() {
    let credit = SoundCredit(
      name: "Rain", fileName: "rain", soundName: "Heavy Rain", author: "Jane Doe", license: .ccBy4,
      soundUrl: nil)
    #expect(credit.attributionText == "\"Heavy Rain\" by Jane Doe")
  }
}
