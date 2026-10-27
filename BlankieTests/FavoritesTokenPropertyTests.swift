//
//  FavoritesTokenPropertyTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Seeded property tests for the `starredItems` token grammar and its list operations.
//  Failure messages carry the seed and step. The list suite restores GlobalSettings.shared.
//

import Foundation
import SwiftUI
import Testing

@testable import Blankie

/// SplitMix64: small, deterministic, and good enough for test-case generation.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private enum Gen {
  /// Characters that stress the grammar, such as the delimiter, the prefix
  /// letters, UUID hex and dashes, whitespace, and non-ASCII.
  static let alphabet = Array("solo:ABCDEFabcdef0123456789-_ .é雨🌧")

  static func uuid(_ rng: inout SeededGenerator) -> UUID {
    let a = rng.next()
    let b = rng.next()
    return withUnsafeBytes(of: (a, b)) { raw in
      UUID(uuid: raw.load(as: uuid_t.self))
    }
  }

  static func string(_ rng: inout SeededGenerator, maxLength: Int = 12) -> String {
    let length = Int.random(in: 0...maxLength, using: &rng)
    return String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
  }

  /// A file name, sometimes shaped like another token to probe exclusivity.
  static func fileName(_ rng: inout SeededGenerator) -> String {
    switch Int.random(in: 0..<6, using: &rng) {
    case 0: return ""
    case 1: return "solo:" + string(&rng)
    case 2: return uuid(&rng).uuidString
    case 3: return ["allSounds", "quickMix"].randomElement(using: &rng)!
    default: return string(&rng)
    }
  }

  static func item(_ rng: inout SeededGenerator) -> PlayableItem {
    switch Int.random(in: 0..<4, using: &rng) {
    case 0: return .allSounds
    case 1: return .quickMix
    case 2: return .preset(uuid(&rng))
    default: return .single(fileName: fileName(&rng))
    }
  }
}

// MARK: - Codec properties

@Suite struct FavoritesTokenPropertyTests {
  private static let seed: UInt64 = 0xB1A7_C1E5
  private static let cases = 2_000

  @Test func itemTokenRoundTrips() {
    var rng = SeededGenerator(seed: Self.seed)
    for step in 0..<Self.cases {
      let item = Gen.item(&rng)
      #expect(PlayableItem(token: item.token) == item, "seed \(Self.seed) step \(step): \(item)")
    }
  }

  /// Stored lists then compare equal to what the app writes today.
  @Test func writtenTokenIsAFixedPoint() {
    var rng = SeededGenerator(seed: Self.seed &+ 1)
    for step in 0..<Self.cases {
      let token = Gen.item(&rng).token
      #expect(PlayableItem(token: token)?.token == token, "step \(step): \(token)")
    }
  }

  /// Membership checks compare token strings.
  @Test func distinctItemsHaveDistinctTokens() {
    var rng = SeededGenerator(seed: Self.seed &+ 2)
    var byToken: [String: PlayableItem] = [:]
    for step in 0..<Self.cases {
      let item = Gen.item(&rng)
      if let existing = byToken[item.token] {
        #expect(existing == item, "step \(step): \(existing) and \(item) share \(item.token)")
      }
      byToken[item.token] = item
    }
  }

  @Test func nearMissTokensAreRejected() {
    let uuid = UUID().uuidString
    let nearMisses = [
      "", "allsounds", "AllSounds", "allSounds ", " allSounds", "quickmix", "QuickMix",
      "Solo:rain", "SOLO:rain", "solo", "solo-rain", " solo:rain", "{\(uuid)}",
      String(uuid.dropLast()), uuid + " ", " " + uuid, uuid.replacingOccurrences(of: "-", with: ""),
    ]
    for token in nearMisses {
      #expect(PlayableItem(token: token) == nil, "\(token.debugDescription) should not decode")
    }
  }

  @Test func randomStringsDecodeOnlyIntoTheirShape() {
    var rng = SeededGenerator(seed: Self.seed &+ 3)
    for step in 0..<Self.cases {
      let token = Gen.string(&rng, maxLength: 40)
      switch PlayableItem(token: token) {
      case .allSounds: #expect(token == "allSounds", "step \(step)")
      case .quickMix: #expect(token == "quickMix", "step \(step)")
      case .single(let fileName): #expect(token == "solo:" + fileName, "step \(step)")
      case .preset(let id): #expect(UUID(uuidString: token) == id, "step \(step)")
      case nil:
        #expect(
          token != "allSounds" && token != "quickMix" && !token.hasPrefix("solo:")
            && UUID(uuidString: token) == nil, "step \(step): \(token.debugDescription)")
      }
    }
  }

  /// The app writes uppercase `uuidString`, so stored lists stay canonical.
  @Test func lowercasePresetTokenCanonicalizesToUppercase() {
    let id = UUID()
    let lower = id.uuidString.lowercased()
    #expect(PlayableItem(token: lower) == .preset(id))
    #expect(PlayableItem(token: lower)?.token == id.uuidString)
  }
}

// MARK: - List operation properties

@Suite(.serialized) @MainActor final class FavoritesListPropertyTests {
  private let settings = GlobalSettings.shared
  private let snapshot = DefaultsSnapshot([UserDefaultsKeys.starredItems])
  private let originalStarred: [String]

  private static let seed: UInt64 = 0xFA70_0001
  private static let sequences = 30
  private static let stepsPerSequence = 20

  init() {
    originalStarred = settings.starredItems
    settings.starredItems = []
  }

  isolated deinit {
    settings.starredItems = originalStarred
    snapshot.restore()
  }

  /// A fixed pool so toggles hit already-starred tokens often.
  private func pool(_ rng: inout SeededGenerator) -> [String] {
    var tokens = [GlobalSettings.allSoundsToken, GlobalSettings.quickMixToken]
    tokens += (0..<4).map { _ in Gen.uuid(&rng).uuidString }
    tokens += ["rain", "waves", "a:b", ""].map(GlobalSettings.singleToken(forFileName:))
    return tokens
  }

  private func assertWellFormed(_ list: [String], _ context: String) {
    #expect(Set(list).count == list.count, "duplicate token after \(context): \(list)")
  }

  /// Also checks that no token repeats and that each reorder is a permutation.
  @Test func toggleAndReorderMatchModel() {
    var rng = SeededGenerator(seed: Self.seed)
    for sequence in 0..<Self.sequences {
      let tokens = pool(&rng)
      var model: [String] = []
      settings.setStarredItems([])
      for step in 0..<Self.stepsPerSequence {
        let context = "seed \(Self.seed) sequence \(sequence) step \(step)"
        if model.count > 1, Bool.random(using: &rng) {
          // Same as LibraryView.reorderFavorites, which calls Array.move on the shown tokens.
          let offsets = IndexSet(
            (0..<model.count).filter { _ in Int.random(in: 0..<3, using: &rng) == 0 })
          let destination = Int.random(in: 0...model.count, using: &rng)
          var moved = settings.starredItems
          moved.move(fromOffsets: offsets, toOffset: destination)
          #expect(moved.sorted() == model.sorted(), "reorder lost or added a token, \(context)")
          settings.setStarredItems(moved)
          model.move(fromOffsets: offsets, toOffset: destination)
        } else {
          let token = tokens.randomElement(using: &rng)!
          settings.toggleStarred(token)
          if let index = model.firstIndex(of: token) {
            model.remove(at: index)
          } else {
            model.append(token)
          }
        }
        #expect(settings.starredItems == model, "\(context)")
        assertWellFormed(settings.starredItems, context)
      }
    }
  }

  @Test func doubleToggleIsIdentity() {
    var rng = SeededGenerator(seed: Self.seed &+ 1)
    for sequence in 0..<Self.sequences {
      let tokens = pool(&rng)
      let start = tokens.shuffled(using: &rng).prefix(Int.random(in: 0...tokens.count, using: &rng))
      settings.setStarredItems(Array(start))
      let token = tokens.randomElement(using: &rng)!
      let before = settings.starredItems
      settings.toggleStarred(token)
      if before.contains(token) {
        // Re-adding appends, so only membership and the others' order are restored.
        settings.toggleStarred(token)
        #expect(Set(settings.starredItems) == Set(before), "sequence \(sequence)")
        #expect(
          settings.starredItems.filter { $0 != token } == before.filter { $0 != token },
          "sequence \(sequence)")
      } else {
        settings.toggleStarred(token)
        #expect(settings.starredItems == before, "sequence \(sequence)")
      }
    }
  }

  /// Kept: both special tokens, live presets and existing single sounds (every single sound when
  /// the sound list is unknown). Undecodable tokens are dropped.
  @Test func pruneKeepsAnOrderedSubsequenceByTheRules() {
    var rng = SeededGenerator(seed: Self.seed &+ 2)
    for sequence in 0..<Self.sequences {
      var tokens = pool(&rng)
      tokens.append(Gen.string(&rng))  // usually garbage
      let list = Array(tokens.shuffled(using: &rng))
      let presetIDs = list.filter { UUID(uuidString: $0) != nil }
      let validPresets = Set(presetIDs.filter { _ in Bool.random(using: &rng) })
      let validSounds: Set<String>? =
        Bool.random(using: &rng)
        ? Set(["rain", "a:b"].filter { _ in Bool.random(using: &rng) }) : nil

      settings.setStarredItems(list)
      settings.pruneStarredItems(validPresetIDs: validPresets, validSoundFileNames: validSounds)

      let expected = list.filter { token in
        if token == "allSounds" || token == "quickMix" { return true }
        if token.hasPrefix("solo:") {
          return validSounds.map { $0.contains(String(token.dropFirst(5))) } ?? true
        }
        if let id = UUID(uuidString: token) { return validPresets.contains(id.uuidString) }
        return false
      }
      #expect(settings.starredItems == expected, "seed \(Self.seed &+ 2) sequence \(sequence)")
    }
  }
}
