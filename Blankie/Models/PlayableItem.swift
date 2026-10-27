//
//  PlayableItem.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//
//  What a favorite, lock screen, CarPlay or Siri entry points at, and the one
//  codec for the persisted `starredItems` tokens. Tokens are user data and must
//  not change (pinned by WidgetTokenGrammarTests and PlayableItemTests).
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
  /// A single sound, identified by its stable `fileName`.
  case single(fileName: String)

  // Canonical token strings. These are persisted, so never change them.
  private static let allSoundsToken = "allSounds"
  private static let quickMixToken = "quickMix"
  /// A single sound is stored as `"solo:<fileName>"`. Keep the "solo" spelling, or every
  /// starred single sound is lost.
  static let singleTokenPrefix = "solo:"

  /// Decodes a persisted `starredItems` token, or nil if it isn't a valid one.
  /// The special tokens and the single sound prefix are checked before falling back to a
  /// preset UUID, so the four shapes stay mutually exclusive.
  init?(token: String) {
    switch token {
    case Self.allSoundsToken:
      self = .allSounds
    case Self.quickMixToken:
      self = .quickMix
    default:
      if token.hasPrefix(Self.singleTokenPrefix) {
        self = .single(fileName: String(token.dropFirst(Self.singleTokenPrefix.count)))
      } else if let id = UUID(uuidString: token) {
        self = .preset(id)
      } else {
        return nil
      }
    }
  }

  /// The persisted token for this item, matching the strings in App Group storage.
  var token: String {
    switch self {
    case .allSounds:
      return Self.allSoundsToken
    case .quickMix:
      return Self.quickMixToken
    case .single(let fileName):
      return Self.singleTokenPrefix + fileName
    case .preset(let id):
      return id.uuidString
    }
  }
}
