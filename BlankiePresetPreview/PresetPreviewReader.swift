//
//  PresetPreviewReader.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 6/22/26.
//
//  Reads the name, sounds and artwork from a `.blankie` archive for the Quick
//  Look card, without the app's managers, SwiftData or audio stack.
//

import Foundation
import ZIPFoundation

enum PresetPreviewReader {
  /// `Sendable` so it can leave the detached read task. Artwork stays `Data`
  /// and is decoded on the main actor.
  struct PresetInfo: Sendable {
    let name: String
    let creator: String?
    let soundCount: Int
    let artworkData: Data?
    /// Accent token (`"teal"`), or nil for the app default.
    let accentColorName: String?
    /// Selected sounds' SF Symbols for the no-artwork montage. Empty shows the Blankie mark.
    let iconNames: [String]
    /// The default preset always shows the brand mark.
    let isDefault: Bool
  }

  /// Per-entry decompressed size cap (zip-bomb guard for a memory-limited extension).
  /// The preview reads only `preset.json` and one image, never the audio.
  private static let maxEntryBytes = 8 * 1024 * 1024

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
    for name in ["artwork.jpg", "animatedPreview.jpg"] {
      if let data = entryData(in: archive, path: name) {
        artworkData = data
        break
      }
    }

    let selected = preset.soundStates.filter(\.isSelected)
    let creator = preset.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return PresetInfo(
      name: preset.name,
      creator: (creator?.isEmpty == false) ? creator : nil,
      soundCount: selected.count,
      artworkData: artworkData,
      accentColorName: preset.accentColorName,
      iconNames: resolveIcons(for: selected, in: archive),
      isDefault: preset.isDefault ?? false
    )
  }

  /// Same precedence as the app: icon override, then custom sound icon, then the
  /// built-in catalog. Unmapped sounds are dropped.
  private static func resolveIcons(
    for selected: [ArchivedSoundState], in archive: Archive
  ) -> [String] {
    var overrides: [String: String] = [:]  // baseName -> customIconName
    var customIcons: [String: String] = [:]  // baseName -> systemIconName
    if let data = entryData(in: archive, path: "sounds/metadata.json"),
      let manifest = try? JSONDecoder().decode(ArchivedSoundsManifest.self, from: data)
    {
      for sound in manifest.customSounds {
        if let icon = sound.systemIconName { customIcons[baseName(sound.fileName)] = icon }
      }
      for custom in manifest.builtInCustomizations {
        if let icon = custom.customIconName { overrides[baseName(custom.fileName)] = icon }
      }
    }

    return selected.compactMap { state in
      let key = baseName(state.fileName)
      return overrides[key]
        ?? customIcons[key]
        ?? BuiltInSoundIcons.icon(for: key)
    }
  }

  /// `soundStates` use base names but `sounds/metadata.json` (and legacy presets)
  /// include the extension, so both sides key on the base name.
  private static let audioExtensions: Set<String> = [
    "m4a", "mp3", "wav", "aif", "aiff", "flac", "ogg", "opus", "caf", "aac", "au",
  ]

  private static func baseName(_ fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    guard !ext.isEmpty, audioExtensions.contains(ext) else { return fileName }
    return (fileName as NSString).deletingPathExtension
  }

  /// Extracts one entry into memory, aborting past `maxEntryBytes`.
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

/// Subset of the app's `Preset`.
private struct ArchivedPreset: Decodable {
  let name: String
  let creatorName: String?
  let soundStates: [ArchivedSoundState]
  let accentColorName: String?
  let isDefault: Bool?
}

private struct ArchivedSoundState: Decodable {
  let fileName: String
  let isSelected: Bool
}

/// Subset of the app's `SoundsManifest` (`sounds/metadata.json`), for icons only.
private struct ArchivedSoundsManifest: Decodable {
  let customSounds: [ArchivedCustomSound]
  let builtInCustomizations: [ArchivedCustomization]

  struct ArchivedCustomSound: Decodable {
    let fileName: String
    let systemIconName: String?
  }

  struct ArchivedCustomization: Decodable {
    let fileName: String
    let customIconName: String?
  }
}
