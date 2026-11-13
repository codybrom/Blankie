//
//  UnsavedMix.swift
//  Blankie
//
//  Created by Cody Bromley on 10/29/26.
//
//  A mix started by adding a sound to a single sound. It lives only in memory
//  until it's saved as a preset, so quitting always loses it.
//

import Foundation

nonisolated struct UnsavedMix: Equatable, Sendable {
  /// Follows the sounds that are on (see `name(forTitles:)`).
  var name: String
  /// The single sound the mix grew from.
  let originSoundFileName: String
  /// The mix's sounds in the order they were added, including any switched off.
  var soundFileNames: [String]

  /// "Rain + Waves Mix" for two sounds and "Custom Mix" for more. `nil` for fewer than two,
  /// which keeps the name it had.
  static func name(forTitles titles: [String]) -> String? {
    switch titles.count {
    case 0, 1: return nil
    case 2: return generatedName(first: titles[0], second: titles[1])
    default: return String(localized: "Custom Mix")
    }
  }

  /// "Rain + Waves Mix", from two localized sound titles.
  static func generatedName(first: String, second: String) -> String {
    String(
      localized: "\(first) + \(second) Mix",
      comment: "Name of an unsaved mix made from two sounds, like Rain + Waves Mix.")
  }
}
