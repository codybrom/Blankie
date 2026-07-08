//
//  BuiltInSoundIcons.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 7/8/26.
//
//  Maps a built-in sound's file name to its SF Symbol, read from the same
//  bundled `sounds.json` the app ships. Bundling that single source of truth
//  keeps the Quick Look fallback's sound icons in sync with the app instead of
//  duplicating an icon table that would drift as sounds are added.
//

import Foundation

enum BuiltInSoundIcons {
  /// `fileName` → `systemIconName` for every built-in sound, parsed once.
  private static let map: [String: String] = {
    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
    else { return [:] }
    return Dictionary(
      catalog.sounds.map { ($0.fileName, $0.systemIconName) },
      uniquingKeysWith: { first, _ in first })
  }()

  static func icon(for fileName: String) -> String? { map[fileName] }

  /// `sounds.json` is a top-level object wrapping the sound records in a
  /// `sounds` array, not a bare array.
  private struct Catalog: Decodable {
    let sounds: [Entry]
  }

  /// The only two fields the fallback needs from each `sounds.json` record.
  private struct Entry: Decodable {
    let fileName: String
    let systemIconName: String
  }
}
