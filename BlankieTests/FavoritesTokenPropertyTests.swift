//
//  FavoritesTokenPropertyTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Seeded property tests for the `starredItems` token grammar and the list
//  operations on it. Each test generates its inputs from a fixed seed, so a
//  failure reproduces exactly. The seed and step are in the failure message.
//
//  The list suite is serialized and main-actor because it drives
//  GlobalSettings.shared. It restores the touched value and UserDefaults key.
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
    default: return .solo(fileName: fileName(&rng))
    }
  }
}

// MARK: - Codec properties

@Suite struct FavoritesTokenPropertyTests {
  private static let seed: UInt64 = 0xB1A7_C1E5
  private static let cases = 2_000

  /// Decoding an item's token gives back the same item, for every shape.
  @Test func itemTokenRoundTrips() {
    var rng = SeededGenerator(seed: Self.seed)
    for step in 0..<Self.cases {
      let item = Gen.item(&rng)
      #expect(PlayableItem(token: item.token) == item, "seed \(Self.seed) step \(step): \(item)")
    }
  }

  /// A token the app wrote decodes and re-encodes to the identical string, so
  /// a stored list compares equal to what the app would write today.
  @Test func writtenTokenIsAFixedPoint() {
    var rng = SeededGenerator(seed: Self.seed &+ 1)
    for step in 0..<Self.cases {
      let token = Gen.item(&rng).token
      #expect(PlayableItem(token: token)?.token == token, "step \(step): \(token)")
    }
  }

  /// Distinct items never share a token, so membership by string is sound.
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

  /// Near misses of each shape are rejected rather than read as something else.
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

  /// Random strings decode only when they really have one of the four shapes.
  @Test func randomStringsDecodeOnlyIntoTheirShape() {
    var rng = SeededGenerator(seed: Self.seed &+ 3)
    for step in 0..<Self.cases {
      let token = Gen.string(&rng, maxLength: 40)
      switch PlayableItem(token: token) {
      case .allSounds: #expect(token == "allSounds", "step \(step)")
      case .quickMix: #expect(token == "quickMix", "step \(step)")
      case .solo(let fileName): #expect(token == "solo:" + fileName, "step \(step)")
      case .preset(let id): #expect(UUID(uuidString: token) == id, "step \(step)")
      case nil:
        #expect(
          token != "allSounds" && token != "quickMix" && !token.hasPrefix("solo:")
            && UUID(uuidString: token) == nil, "step \(step): \(token.debugDescription)")
      }
    }
  }

  /// A lowercase preset UUID decodes but re-encodes uppercase. The app only
  /// ever writes `uuidString` (uppercase), so stored lists stay canonical. This
  /// pins the behavior in case a lowercase source ever appears.
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
    tokens += ["rain", "waves", "a:b", ""].map(GlobalSettings.soloToken(forFileName:))
    return tokens
  }

  private func assertWellFormed(_ list: [String], _ context: String) {
    #expect(Set(list).count == list.count, "duplicate token after \(context): \(list)")
  }

  /// Random toggles and reorders match a reference model, never duplicate a
  /// token, and a reorder is always a permutation.
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

  /// Toggling twice restores an unstarred token's list exactly, and a starred
  /// token's membership and the others' order.
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

  /// Prune keeps exactly the tokens the rules allow, in their original order.
  /// Those are both special tokens, live presets, and solo sounds that still
  /// exist (all of them when the sound list is unknown). Undecodable tokens are
  /// dropped.
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
