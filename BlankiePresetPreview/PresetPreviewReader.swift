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
import ZIPFoundation

enum PresetPreviewReader {
  /// Plain, `Sendable` value so it can cross out of the detached read task. The
  /// artwork stays as raw `Data` here and is decoded to a `UIImage` on the main
  /// actor in the view, mirroring how the app avoids returning `UIImage` from
  /// detached work.
  struct PresetInfo {
    let name: String
    let creator: String?
    let soundCount: Int
    let artworkData: Data?
  }

  /// Cap on a single decompressed entry. `.blankie` files are untrusted shared
  /// input, so refuse to balloon memory on a crafted (zip-bomb) archive — the
  /// real payloads here are a tiny JSON and a small preview image.
  private static let maxEntryBytes = 32 * 1024 * 1024

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

    var artworkData: Data?
    for name in ["animatedPreview.jpg", "artwork.jpg"] {
      if let data = entryData(in: archive, path: name) {
        artworkData = data
        break
      }
    }

    let creator = preset.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return PresetInfo(
      name: preset.name,
      creator: (creator?.isEmpty == false) ? creator : nil,
      soundCount: preset.soundStates.filter(\.isSelected).count,
      artworkData: artworkData
    )
  }

  /// Extract a single archive entry into memory without unpacking the whole zip,
  /// aborting if the decompressed size exceeds `maxEntryBytes`.
  private static func entryData(in archive: Archive, path: String) -> Data? {
    guard let entry = archive[path] else { return nil }
    var data = Data()
    do {
      _ = try archive.extract(entry) { chunk in
        data.append(chunk)
        if data.count > maxEntryBytes { throw ReadError.unreadableArchive }
      }
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
