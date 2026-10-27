//
//  PlayableItemTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 7/8/26.
//
//  PlayableItem is the codec for persisted `starredItems` tokens, so its encodings must stay
//  byte-compatible with what App Group storage already holds.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PlayableItemTests {

  // MARK: - Encode

  @Test func encodesEachShapeToItsPersistedToken() {
    #expect(PlayableItem.allSounds.token == "allSounds")
    #expect(PlayableItem.quickMix.token == "quickMix")
    #expect(PlayableItem.solo(fileName: "rain").token == "solo:rain")
    let id = UUID()
    #expect(PlayableItem.preset(id).token == id.uuidString)
  }

  // MARK: - Decode

  @Test func decodesEachShape() {
    #expect(PlayableItem(token: "allSounds") == .allSounds)
    #expect(PlayableItem(token: "quickMix") == .quickMix)
    #expect(PlayableItem(token: "solo:rain") == .solo(fileName: "rain"))
    let id = UUID()
    #expect(PlayableItem(token: id.uuidString) == .preset(id))
  }

  @Test func rejectsInvalidTokens() {
    #expect(PlayableItem(token: "") == nil)
    #expect(PlayableItem(token: "not-a-uuid") == nil)
    #expect(PlayableItem(token: "AllSounds") == nil)  // case-sensitive
  }

  // MARK: - Round-trip

  @Test func roundTripsThroughToken() {
    let items: [PlayableItem] = [
      .allSounds, .quickMix, .solo(fileName: "distant-thunder"), .preset(UUID()),
    ]
    for item in items {
      #expect(PlayableItem(token: item.token) == item)
    }
  }

  /// Only the first `solo:` is stripped, so a delimiter in the file name survives.
  @Test func soloPreservesColonInFileName() {
    let item = PlayableItem.solo(fileName: "a:b")
    #expect(item.token == "solo:a:b")
    #expect(PlayableItem(token: "solo:a:b") == item)
  }

  // MARK: - Mutual exclusivity

  @Test func shapesAreMutuallyExclusive() {
    #expect(PlayableItem(token: "allSounds") != .preset(UUID()))
    if case .preset = PlayableItem(token: "solo:rain") { Issue.record("solo parsed as preset") }
    if case .solo = PlayableItem(token: UUID().uuidString) { Issue.record("uuid parsed as solo") }
    if case .preset = PlayableItem(token: "quickMix") { Issue.record("quickMix parsed as preset") }
  }

  // MARK: - GlobalSettings forwarding stays byte-compatible

  @Test func matchesGlobalSettingsTokens() {
    #expect(PlayableItem.allSounds.token == GlobalSettings.allSoundsToken)
    #expect(PlayableItem.quickMix.token == GlobalSettings.quickMixToken)
    #expect(
      PlayableItem.solo(fileName: "rain").token == GlobalSettings.soloToken(forFileName: "rain"))
  }
}
