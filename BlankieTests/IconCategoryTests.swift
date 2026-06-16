//
//  IconCategoryTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/6/26.
//

import Foundation
import Testing

@testable import Blankie

/// Guards the three-way alignment between the IconCategory enum, the top-level
/// keys of icon-categories.json, and the string catalog.
@Suite struct IconCategoryTests {

  /// icon-categories.json top-level keys and IconCategory cases must match exactly.
  @Test func enumMatchesJSONKeys() {
    let jsonKeys = Set(IconData.iconCategories.keys)
    let enumKeys = Set(IconCategory.allCases.map(\.rawValue))

    #expect(!jsonKeys.isEmpty, "icon-categories.json failed to load")
    #expect(
      jsonKeys.subtracting(enumKeys) == [], "icon-categories.json keys with no IconCategory case")
    #expect(
      enumKeys.subtracting(jsonKeys) == [], "IconCategory cases missing from icon-categories.json")
  }

  /// Every category must contribute at least one icon to the picker.
  @Test func everyCategoryHasIcons() {
    for category in IconCategory.allCases {
      #expect(!category.icons.isEmpty, "Category '\(category.rawValue)' has no icons")
    }
  }

  /// Every category name must have an entry in the compiled string catalog for
  /// every locale the app ships Localizable strings in.
  @Test func categoryNamesAreLocalized() {
    let appBundle = Bundle(for: AudioManager.self)
    let sentinel = "<<missing>>"
    var checkedLocales = 0

    for locale in appBundle.localizations where locale != "Base" {
      guard let lprojPath = appBundle.path(forResource: locale, ofType: "lproj"),
        let lproj = Bundle(path: lprojPath)
      else { continue }

      // Skip locales without a Localizable table (e.g. InfoPlist-only).
      guard lproj.localizedString(forKey: "Cancel", value: sentinel, table: nil) != sentinel
      else { continue }
      checkedLocales += 1

      for category in IconCategory.allCases {
        #expect(
          lproj.localizedString(forKey: category.rawValue, value: sentinel, table: nil) != sentinel,
          "Category '\(category.rawValue)' has no '\(locale)' entry in the string catalog")
      }
    }

    #expect(
      checkedLocales >= 13, "Expected the category names to be checked in all shipped locales")
  }
}
