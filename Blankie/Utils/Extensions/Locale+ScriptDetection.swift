//
//  Locale+ScriptDetection.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/25.
//

import Foundation

extension Locale {
  enum ScriptCategory {
    case standard  // Regular weight, standard size
    case cjk  // Thin weight, standard size
    case dense  // Thin weight, larger size
  }

  /// Scripts that work well with standard font styling
  private static let standardScripts: Set<Locale.Script> = [
    .latin,
    .greek,
    .cyrillic,
    .hebrew,
    .arabic,
    .georgian,
    .armenian,
    .ethiopic,
    .cherokee,
  ]

  /// CJK scripts that need thin weight but standard size
  private static let cjkScripts: Set<Locale.Script> = [
    .hiragana,
    .katakana,
    .japanese,
    .korean,
    .hanSimplified,
    .hanTraditional,
  ]

  /// Get the script category for font styling
  var scriptCategory: ScriptCategory {
    guard let script = self.language.script else { return .standard }

    if Self.standardScripts.contains(script) {
      return .standard
    } else if Self.cjkScripts.contains(script) {
      return .cjk
    } else {
      return .dense
    }
  }

  /// Whether this locale's script has dense strokes that benefit from thinner font weight
  var hasDenseScript: Bool {
    scriptCategory != .standard
  }

  /// Whether this locale's script benefits from slightly larger font size
  var needsLargerFontSize: Bool {
    scriptCategory == .dense
  }
}
