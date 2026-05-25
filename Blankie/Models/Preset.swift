//
//  Preset.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct AnimatedArtworkRef: Codable, Equatable, Hashable {
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

/// UI-side enum for the Edit Preset picker, so SwiftUI can bind to a
/// concrete value even when the underlying model stores `nil`.
enum PresetViewModeSelection: Hashable {
  case useDefault
  case grid
  case list

  init(_ mode: PresetViewMode?) {
    switch mode {
    case .some(.grid): self = .grid
    case .some(.list): self = .list
    case .none: self = .useDefault
    }
  }

  var asOptional: PresetViewMode? {
    switch self {
    case .useDefault: return nil
    case .grid: return .grid
    case .list: return .list
    }
  }
}

struct Preset: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var soundStates: [PresetState]
  let isDefault: Bool
  let createdVersion: String?
  var lastModifiedVersion: String?
  var soundOrder: [String]?
  var creatorName: String?
  var artworkId: UUID?  // Reference to PresetArtwork in SwiftData

  // Animated artwork
  var animatedArtwork: AnimatedArtworkRef?
  var staticArtworkPath: String?

  // Preset order for navigation
  var order: Int?

  // Import metadata - tracks if this preset was imported
  var isImported: Bool?
  var originalId: UUID?  // Original ID from imported preset for duplicate detection

  // Mood/category tags
  var moods: [SoundMood]?

  // Custom accent color
  var accentColorName: String?

  /// Per-preset view-mode override (Grid vs List). `nil` = follow the
  /// app-wide `GlobalSettings.showingListView` setting.
  var viewMode: PresetViewMode?

  /// Per-preset override for the background-artwork blur radius (in points).
  /// `nil` = follow the app-wide `GlobalSettings.backgroundBlurRadius`.
  var backgroundBlurRadius: Double?

  var accentColor: Color? {
    guard let name = accentColorName else { return nil }
    return Color(fromString: name)
  }

  /// Display name for the preset (shows "All Blankie Sounds" for default preset)
  var displayName: String {
    return isDefault ? "All Blankie Sounds" : name
  }

  /// Title to show when this preset is active (shows "Blankie" for default preset)
  var activeTitle: String {
    return isDefault ? "Blankie" : name
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

  func validate() -> Bool {
    // Preset must have at least one sound
    guard !soundStates.isEmpty else {
      debugLog("❌ Preset: Must contain at least one sound")
      return false
    }

    // Check that all sounds referenced in the preset actually exist
    let availableSounds = Set(AudioManager.shared.sounds.map(\.fileName))
    let presetSounds = soundStates.map(\.fileName)

    for soundFileName in presetSounds where !availableSounds.contains(soundFileName) {
      debugLog("❌ Preset: References non-existent sound '\(soundFileName)'")
      return false
    }

    // Validate volume ranges
    guard soundStates.allSatisfy({ $0.volume >= 0 && $0.volume <= 1 }) else {
      debugLog("❌ Preset: Invalid volume range")
      return false
    }

    // Validate name
    guard !name.isEmpty else {
      debugLog("❌ Preset: Empty name")
      return false
    }

    // Note: Animated artwork validation is not included here because:
    // - ODR resources may be purged by the system
    // - Files can be re-downloaded on demand
    // - Missing animated artwork should not prevent preset from being valid
    // Instead, animated artwork availability is checked at presentation time

    return true
  }
}

// MARK: - Transferable

extension UTType {
  static let blankiePreset = UTType(exportedAs: "com.codybrom.blankie.preset")
}

// Wrapper for the exported file with proper metadata
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
