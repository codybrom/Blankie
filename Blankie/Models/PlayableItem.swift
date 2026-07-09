//
//  PlayableItem.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//
//  A single identity for "what a favorite / lock-screen / CarPlay / Siri entry
//  points at": the default preset, a saved preset, Quick Mix, or a soloed sound.
//  This is the one place the persisted `starredItems` token grammar is encoded
//  and decoded — every surface that used to re-parse the four token shapes by
//  hand can route through here instead. The `token` output is byte-identical to
//  the strings already stored in App Group storage, so it is user data and must
//  not change (pinned by WidgetTokenGrammarTests / PlayableItemTests).
//

import Foundation

/// The four mutually exclusive things a favorite token can refer to.
nonisolated enum PlayableItem: Equatable, Hashable {
  /// The default preset ("All Blankie Sounds").
  case allSounds
  /// A saved preset, by id.
  case preset(UUID)
  /// The transient Quick Mix.
  case quickMix
  /// A soloed sound, identified by its stable `fileName`.
  case solo(fileName: String)

  // Canonical token strings. These are the persisted grammar — do not change.
  private static let allSoundsToken = "allSounds"
  private static let quickMixToken = "quickMix"
  /// A soloed sound is stored as `"solo:<fileName>"`.
  static let soloTokenPrefix = "solo:"

  /// Decodes a persisted `starredItems` token, or nil if it isn't a valid one.
  /// The special tokens and the solo prefix are checked before falling back to a
  /// preset UUID, so the four shapes stay mutually exclusive.
  init?(token: String) {
    switch token {
    case Self.allSoundsToken:
      self = .allSounds
    case Self.quickMixToken:
      self = .quickMix
    default:
      if token.hasPrefix(Self.soloTokenPrefix) {
        self = .solo(fileName: String(token.dropFirst(Self.soloTokenPrefix.count)))
      } else if let id = UUID(uuidString: token) {
        self = .preset(id)
      } else {
        return nil
      }
    }
  }

  /// The persisted token for this item — identical to the strings already in
  /// App Group storage.
  var token: String {
    switch self {
    case .allSounds:
      return Self.allSoundsToken
    case .quickMix:
      return Self.quickMixToken
    case .solo(let fileName):
      return Self.soloTokenPrefix + fileName
    case .preset(let id):
      return id.uuidString
    }
  }
}
