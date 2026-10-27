//
//  Preset.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os

nonisolated struct AnimatedArtworkRef: Codable, Equatable, Hashable {
  enum Source: String, Codable, CaseIterable {
    case auto
    case bundled
    case custom
  }

  var source: Source
  var loopPath: String?
  var previewPath: String?  // 3:4 portrait preview
  var squarePreviewPath: String?  // 1:1 square preview (used as static artwork fallback)
  var preferredAspect: String?
  var bundledIdentifier: String?

  init(
    source: Source,
    loopPath: String? = nil,
    previewPath: String? = nil,
    squarePreviewPath: String? = nil,
    preferredAspect: String? = nil,
    bundledIdentifier: String? = nil
  ) {
    self.source = source
    self.loopPath = loopPath
    self.previewPath = previewPath
    self.squarePreviewPath = squarePreviewPath
    self.preferredAspect = preferredAspect
    self.bundledIdentifier = bundledIdentifier
  }
}

/// Per-preset override for the sound-layout mode. `nil` on a preset means
/// "follow the app-wide default" (`GlobalSettings.showingListView`).
enum PresetViewMode: String, Codable, CaseIterable {
  case grid
  case list
}

nonisolated struct Preset: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var soundStates: [PresetState]
  let isDefault: Bool
  let createdVersion: String?
  var lastModifiedVersion: String?
  var soundOrder: [String]?
  var creatorName: String?
  var artworkId: UUID?  // Reference to PresetArtwork in SwiftData

  var animatedArtwork: AnimatedArtworkRef?
  var staticArtworkPath: String?

  var order: Int?

  var isImported: Bool?
  var originalId: UUID?  // Original ID from imported preset for duplicate detection

  var moods: [SoundMood]?

  var accentColorName: String?

  /// Per-preset view-mode override (Grid vs List). `nil` = follow the
  /// app-wide `GlobalSettings.showingListView` setting.
  var viewMode: PresetViewMode?

  /// Legacy per-preset blur (in points), kept so older presets decode. Never
  /// applied (blur is the global `GlobalSettings.backgroundBlurRadius`). Cleared on save.
  var backgroundBlurRadius: Double?

  var accentColor: Color? {
    guard let name = accentColorName else { return nil }
    return Color(fromString: name)
  }

  /// Display name for the preset (shows "All Blankie Sounds" for default preset)
  var displayName: String {
    return isDefault ? String(localized: "All Blankie Sounds") : name
  }

  /// Title to show when this preset is active. The default preset keeps its
  /// one name ("All Blankie Sounds") here too.
  var activeTitle: String {
    displayName
  }

  static func == (lhs: Preset, rhs: Preset) -> Bool {
    lhs.id == rhs.id && lhs.name == rhs.name && lhs.soundStates == rhs.soundStates
      && lhs.isDefault == rhs.isDefault && lhs.createdVersion == rhs.createdVersion
      && lhs.lastModifiedVersion == rhs.lastModifiedVersion && lhs.soundOrder == rhs.soundOrder
      && lhs.creatorName == rhs.creatorName && lhs.artworkId == rhs.artworkId
      && lhs.animatedArtwork == rhs.animatedArtwork
      && lhs.staticArtworkPath == rhs.staticArtworkPath
      && lhs.order == rhs.order
      && lhs.isImported == rhs.isImported
      && lhs.moods == rhs.moods
      && lhs.accentColorName == rhs.accentColorName
      && lhs.viewMode == rhs.viewMode
      && lhs.backgroundBlurRadius == rhs.backgroundBlurRadius
  }

  @MainActor func validate() -> Bool {
    // An empty preset is valid: it opens, and its editor is how it gets
    // sounds. Playback coerces "play" over nothing to paused.

    let availableSounds = Set(AudioManager.shared.sounds.map(\.fileName))
    let presetSounds = soundStates.map(\.fileName)

    for soundFileName in presetSounds where !availableSounds.contains(soundFileName) {
      Logger.presets.debug("Preset: References non-existent sound '\(soundFileName)'")
      return false
    }

    guard soundStates.allSatisfy({ $0.volume >= 0 && $0.volume <= 1 }) else {
      Logger.presets.error("Preset: Invalid volume range")
      return false
    }

    guard !name.isEmpty else {
      Logger.presets.debug("Preset: Empty name")
      return false
    }

    // Animated artwork isn't validated here: its asset pack can be purged and
    // re-downloaded, so availability is checked at presentation time.

    return true
  }
}

// MARK: - Transferable

extension UTType {
  nonisolated static let blankiePreset = UTType(exportedAs: "com.codybrom.blankie.preset")
}

struct BlankiePresetFile: Transferable {
  let url: URL
  let presetName: String

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .blankiePreset) { file in
      SentTransferredFile(file.url, allowAccessingOriginalFile: true)
    }
    .suggestedFileName { file in
      "\(file.presetName).blankie"
    }
  }
}
