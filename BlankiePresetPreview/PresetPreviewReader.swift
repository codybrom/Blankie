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
  struct PresetInfo: Sendable {
    let name: String
    let creator: String?
    let soundCount: Int
    let artworkData: Data?
    /// The preset's accent-color token (`"teal"`, `"indigo"`, …) or `nil` to
    /// follow the app default. Resolved to a `Color` in the view.
    let accentColorName: String?
    /// SF Symbols for the preset's selected sounds, in order, so the no-artwork
    /// fallback can render the same sound montage the app shows. Empty falls
    /// back to the Blankie mark.
    let iconNames: [String]
    /// The exported default preset ("All Blankie Sounds"), which always shows
    /// the brand mark rather than a montage.
    let isDefault: Bool
  }

  /// Cap on a single decompressed *entry* — not the whole archive. The preview
  /// only ever extracts `preset.json` (kilobytes) and one preview image (well
  /// under a megabyte), so 8 MB clears every legitimate payload with room to
  /// spare while refusing to balloon memory on a crafted (zip-bomb) entry. A
  /// large `.blankie` is fine: its bulk is custom-sound audio, which the preview
  /// never reads. The cap is kept low because this Quick Look extension runs in
  /// a tight memory sandbox.
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
    for name in ["animatedPreview.jpg", "artwork.jpg"] {
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

  /// Resolve each selected sound to its SF Symbol, in preset order, so the
  /// no-artwork fallback shows the preset's own sounds. Mirrors the app's icon
  /// precedence: a per-preset icon override wins, then a custom sound's own
  /// icon, then the built-in catalog. Sounds we can't map are dropped rather
  /// than shown as a generic placeholder.
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

  /// A sound's file name reaches the fallback in two forms: a preset's
  /// `soundStates` reference both built-ins and custom sounds by their base name
  /// (no extension), while `sounds/metadata.json` stores custom sounds *with*
  /// the extension (and legacy presets may carry a built-in's extension). Strip
  /// a known audio extension so both sides key on the same base name.
  private static let audioExtensions: Set<String> = [
    "m4a", "mp3", "wav", "aif", "aiff", "flac", "ogg", "opus", "caf", "aac", "au",
  ]

  private static func baseName(_ fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    guard !ext.isEmpty, audioExtensions.contains(ext) else { return fileName }
    return (fileName as NSString).deletingPathExtension
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
  let accentColorName: String?
  let isDefault: Bool?
}

private struct ArchivedSoundState: Decodable {
  let fileName: String
  let isSelected: Bool
}

/// A subset of the app's `SoundsManifest` (`sounds/metadata.json`), read only
/// for the sounds' icons.
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
