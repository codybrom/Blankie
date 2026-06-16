//
//  LocaleScriptDetectionTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Drives per-locale font styling. Latin/Cyrillic/etc. stay standard; CJK gets
//  thin weight; dense scripts get thin + larger. A misclassification ships the
//  wrong weight/size for a whole language.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct LocaleScriptDetectionTests {

  @Test func standardScriptsAreStandard() {
    #expect(Locale(identifier: "en-Latn").scriptCategory == .standard)
    #expect(Locale(identifier: "ru-Cyrl").scriptCategory == .standard)
    #expect(Locale(identifier: "ar-Arab").scriptCategory == .standard)
    #expect(!Locale(identifier: "en-Latn").hasDenseScript)
    #expect(!Locale(identifier: "en-Latn").needsLargerFontSize)
  }

  @Test func cjkScriptsAreCJK() {
    #expect(Locale(identifier: "zh-Hans").scriptCategory == .cjk)
    #expect(Locale(identifier: "ja-Jpan").scriptCategory == .cjk)
    #expect(Locale(identifier: "ko-Kore").scriptCategory == .cjk)
    // CJK needs thin weight but standard size.
    #expect(Locale(identifier: "zh-Hans").hasDenseScript)
    #expect(!Locale(identifier: "zh-Hans").needsLargerFontSize)
  }

  @Test func otherScriptsAreDense() {
    #expect(Locale(identifier: "th-Thai").scriptCategory == .dense)
    #expect(Locale(identifier: "hi-Deva").scriptCategory == .dense)
    // Dense needs both thin weight and larger size.
    #expect(Locale(identifier: "th-Thai").hasDenseScript)
    #expect(Locale(identifier: "th-Thai").needsLargerFontSize)
  }

  /// A locale with no determinable script falls back to standard.
  @Test func unknownScriptFallsBackToStandard() {
    #expect(Locale(identifier: "und").scriptCategory == .standard)
  }

  /// Shipped localizations are bare identifiers (no explicit script subtag), so
  /// the real runtime path relies on implicit script resolution. Exercise it for
  /// both standard and CJK languages.
  @Test func bareIdentifiersResolveScriptCategory() {
    #expect(Locale(identifier: "en").scriptCategory == .standard)
    #expect(Locale(identifier: "de").scriptCategory == .standard)
    #expect(Locale(identifier: "ja").scriptCategory == .cjk)
    #expect(Locale(identifier: "ko").scriptCategory == .cjk)
    #expect(Locale(identifier: "zh").scriptCategory == .cjk)
  }
}
