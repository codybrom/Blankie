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
