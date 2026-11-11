//
//  LibraryTabsTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 11/11/26.
//

import Foundation
import Testing

@testable import Blankie

/// What each of the iPhone Library's tabs lists, and what search finds.
@Suite @MainActor struct LibraryTabsTests {

  private static func kaleidoscope(_ title: String) -> KaleidoscopeSound {
    KaleidoscopeSound(
      recipe: KaleidoscopeRecipe(
        title: title, fileName: "test-\(title.lowercased())", systemIconName: "sparkles",
        lufs: -23,
        source: KaleidoscopeRecipe.Source(title: "Test", author: "Test", license: "cc0", url: ""),
        attackSec: 3, loopSec: 8,
        layers: [KaleidoscopeRecipe.Layer(name: "Test", tones: [.init(hz: 110, db: 0)])]))
  }

  private static let sounds: [Sound] = [
    TestSound(fileName: "test-waves"), kaleidoscope("Mist"), TestSound(fileName: "test-rain"),
    kaleidoscope("Air"),
  ]

  @Test func tabNamesStayPutBecauseTheChosenTabIsSaved() {
    #expect(LibraryView.Tab.allCases.map(\.rawValue) == ["home", "kaleidoscopes", "sounds"])
  }

  @Test func kaleidoscopesAndSoundsEachListOnlyTheirOwnByName() {
    let glass = LibraryView.listed(
      Self.sounds, kaleidoscopes: true, tab: .kaleidoscopes, isStarred: { _ in false })
    #expect(glass.map(\.title) == ["Air", "Mist"])
    let others = LibraryView.listed(
      Self.sounds, kaleidoscopes: false, tab: .sounds, isStarred: { _ in false })
    #expect(others.map(\.fileName) == ["test-rain", "test-waves"])
  }

  @Test func aTabKeepsItsStarredSoundsButOneListMovesThemToFavorites() {
    let starred: (Sound) -> Bool = { $0.title == "Air" || $0.fileName == "test-rain" }
    let onTab = LibraryView.listed(
      Self.sounds, kaleidoscopes: true, tab: .kaleidoscopes, isStarred: starred)
    #expect(onTab.map(\.title) == ["Air", "Mist"])
    let inOneList = LibraryView.listed(
      Self.sounds, kaleidoscopes: true, tab: nil, isStarred: starred)
    #expect(inOneList.map(\.title) == ["Mist"])
    let soundsInOneList = LibraryView.listed(
      Self.sounds, kaleidoscopes: false, tab: nil, isStarred: starred)
    #expect(soundsInOneList.map(\.fileName) == ["test-waves"])
  }

  @Test func searchMatchesNamesLoosely() {
    #expect(LibraryView.nameMatches("Stillness", query: "still"))
    #expect(LibraryView.nameMatches("Stillness", query: "  NESS "))
    #expect(LibraryView.nameMatches("Coquí Calling", query: "coqui"))
    #expect(!LibraryView.nameMatches("Stillness", query: "rain"))
  }

  @Test func nothingTypedFindsNothing() {
    #expect(!LibraryView.nameMatches("Stillness", query: ""))
    #expect(!LibraryView.nameMatches("Stillness", query: "   "))
  }
}
