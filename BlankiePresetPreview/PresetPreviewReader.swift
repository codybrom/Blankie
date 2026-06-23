//
//  PresetPreviewReader.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 6/22/26.
//
//  Reads just enough of a `.blankie` archive to render the Quick Look card:
//  the preset's name, sound count, and artwork. Self-contained — the extension
//  never touches the app's managers, SwiftData, or audio stack.
//

import Foundation
import UIKit
import ZIPFoundation

enum PresetPreviewReader {
  struct PresetInfo {
    let name: String
    let creator: String?
    let soundCount: Int
    let artwork: UIImage?
  }

  enum ReadError: Error {
    case unreadableArchive
    case missingPreset
  }

  static func read(from url: URL) throws -> PresetInfo {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing { url.stopAccessingSecurityScopedResource() }
    }

    let archive: Archive
    do {
      archive = try Archive(url: url, accessMode: .read)
    } catch {
      throw ReadError.unreadableArchive
    }

    guard let presetData = entryData(in: archive, path: "preset.json") else {
      throw ReadError.missingPreset
    }
    let preset = try JSONDecoder().decode(ArchivedPreset.self, from: presetData)

    var artwork: UIImage?
    for name in ["animatedPreview.jpg", "artwork.jpg"] {
      if let data = entryData(in: archive, path: name), let image = UIImage(data: data) {
        artwork = image
        break
      }
    }

    let creator = preset.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return PresetInfo(
      name: preset.name,
      creator: (creator?.isEmpty == false) ? creator : nil,
      soundCount: preset.soundStates.filter(\.isSelected).count,
      artwork: artwork
    )
  }

  /// Extract a single archive entry into memory without unpacking the whole zip.
  private static func entryData(in archive: Archive, path: String) -> Data? {
    guard let entry = archive[path] else { return nil }
    var data = Data()
    do {
      _ = try archive.extract(entry) { data.append($0) }
    } catch {
      return nil
    }
    return data
  }
}

/// A subset of the app's `Preset` — JSONDecoder ignores the keys we omit.
private struct ArchivedPreset: Decodable {
  let name: String
  let creatorName: String?
  let soundStates: [ArchivedSoundState]
}

private struct ArchivedSoundState: Decodable {
  let isSelected: Bool
}
