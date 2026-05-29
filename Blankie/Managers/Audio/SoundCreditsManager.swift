//
//  SoundCreditsManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/10/25.
//

import SwiftUI

class SoundCreditsManager: ObservableObject {
  static let shared = SoundCreditsManager()
  @Published private(set) var credits: [SoundCredit] = []
  @Published private(set) var loadError: Error?
  private var soundDataMap: [String: SoundData] = [:]

  private init() {
    loadCredits()
  }

  private func loadCredits() {
    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json") else {
      debugLog("Error: sounds.json not found in bundle")
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let container = try JSONDecoder().decode(SoundsContainer.self, from: data)

      DispatchQueue.main.async {
        // Store sound data for later access
        self.soundDataMap = Dictionary(
          uniqueKeysWithValues: container.sounds.map { ($0.title, $0) })

        self.credits = container.sounds.map { sound in
          SoundCredit(
            name: sound.title,
            soundName: sound.soundName,
            author: sound.author,
            license: License(rawValue: sound.license.lowercased()) ?? .cc0,
            soundUrl: URL(string: sound.soundUrl)
          )
        }
      }
    } catch {
      debugLog("Error loading sounds.json: \(error)")
      loadError = error
    }
  }

  func getAuthor(for soundTitle: String) -> String? {
    return soundDataMap[soundTitle]?.author
  }

  func getDescription(for soundTitle: String) -> String? {
    return soundDataMap[soundTitle]?.description
  }

  func getSoundData(for soundTitle: String) -> SoundData? {
    return soundDataMap[soundTitle]
  }
}

extension Sound {
  /// The credited author to display for this sound, or `nil` when there isn't
  /// one. Custom sounds use their stored credit; built-in sounds look the author
  /// up by their original title. Empty strings are treated as absent.
  @MainActor var creditedAuthor: String? {
    if isCustom {
      guard let dataID = customSoundDataID,
        let data = CustomSoundManager.shared.getCustomSound(by: dataID),
        let author = data.creditAuthor, !author.isEmpty
      else { return nil }
      return author
    }
    guard let author = SoundCreditsManager.shared.getAuthor(for: originalTitle),
      !author.isEmpty
    else { return nil }
    return author
  }
}
