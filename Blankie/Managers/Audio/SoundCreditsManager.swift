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

      // Assign synchronously so credits are ready the moment the singleton
      // exists — non-observing callers (e.g. resolvedCredit) read it directly.
      soundDataMap = Dictionary(
        uniqueKeysWithValues: container.sounds.map { ($0.title, $0) })

      credits = container.sounds.map { sound in
        SoundCredit(
          name: sound.title,
          soundName: sound.soundName,
          author: sound.author,
          license: License(rawValue: sound.license.lowercased()) ?? .cc0,
          soundUrl: URL(string: sound.soundUrl)
        )
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

/// A display-ready credit, resolved from sounds.json (built-in) or `CustomSoundData` (custom).
struct ResolvedSoundCredit {
  let workTitle: String?
  let workUrl: URL?
  let author: String?
  let license: License?
  let customLicenseUrl: URL?

  /// The canonical license URL, or the user-supplied one for custom licenses.
  var licenseUrl: URL? {
    license?.url ?? customLicenseUrl
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

  /// The credit to display for this sound, or `nil` when there's nothing to credit.
  @MainActor var resolvedCredit: ResolvedSoundCredit? {
    if isCustom {
      guard let data = customSoundData else { return nil }

      // Explicit credit fields first, then ID3 metadata captured at import.
      let workTitle = nonEmpty(data.id3Title) ?? nonEmpty(data.originalFileName)
      let author = nonEmpty(data.creditAuthor) ?? nonEmpty(data.id3Artist)
      let sourceUrl = nonEmpty(data.creditSourceUrl) ?? nonEmpty(data.id3Url)
      let license = License(rawValue: data.creditLicenseType)

      guard workTitle != nil || author != nil || sourceUrl != nil || license != nil else {
        return nil
      }
      return ResolvedSoundCredit(
        workTitle: workTitle,
        workUrl: sourceUrl.flatMap { URL(string: $0) },
        author: author,
        license: license,
        customLicenseUrl: nonEmpty(data.creditCustomLicenseUrl).flatMap { URL(string: $0) }
      )
    }

    guard let credit = SoundCreditsManager.shared.credits.first(where: { $0.name == originalTitle })
    else { return nil }
    return ResolvedSoundCredit(
      workTitle: credit.soundName,
      workUrl: credit.soundUrl,
      author: credit.author,
      license: credit.license,
      customLicenseUrl: nil
    )
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
