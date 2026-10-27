//
//  BuiltInSoundIcons.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 7/8/26.
//
//  Maps a built-in sound's file name to its SF Symbol, read from the app's
//  bundled `sounds.json`.
//

import Foundation

enum BuiltInSoundIcons {
  /// `fileName` to `systemIconName`, parsed once.
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

  private struct Catalog: Decodable {
    let sounds: [Entry]
  }

  private struct Entry: Decodable {
    let fileName: String
    let systemIconName: String
  }
}
