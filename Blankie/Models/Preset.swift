//
//  Preset.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI
import UniformTypeIdentifiers

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

  // Background customization
  var showBackgroundImage: Bool?
  var useArtworkAsBackground: Bool?
  var backgroundImageId: UUID?  // Reference to PresetArtwork for background
  var backgroundBlurRadius: Double?
  var backgroundOpacity: Double?

  // Preset order for navigation
  var order: Int?

  // Import metadata - tracks if this preset was imported
  var isImported: Bool?
  var originalId: UUID?  // Original ID from imported preset for duplicate detection

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
      && lhs.showBackgroundImage == rhs.showBackgroundImage
      && lhs.useArtworkAsBackground == rhs.useArtworkAsBackground
      && lhs.backgroundImageId == rhs.backgroundImageId
      && lhs.backgroundBlurRadius == rhs.backgroundBlurRadius
      && lhs.backgroundOpacity == rhs.backgroundOpacity
      && lhs.order == rhs.order
      && lhs.isImported == rhs.isImported
  }

  func validate() -> Bool {
    // Preset must have at least one sound
    guard !soundStates.isEmpty else {
      print("❌ Preset: Must contain at least one sound")
      return false
    }

    // Check that all sounds referenced in the preset actually exist
    let availableSounds = Set(AudioManager.shared.sounds.map(\.fileName))
    let presetSounds = soundStates.map(\.fileName)

    for soundFileName in presetSounds where !availableSounds.contains(soundFileName) {
      print("❌ Preset: References non-existent sound '\(soundFileName)'")
      return false
    }

    // Validate volume ranges
    guard soundStates.allSatisfy({ $0.volume >= 0 && $0.volume <= 1 }) else {
      print("❌ Preset: Invalid volume range")
      return false
    }

    // Validate name
    guard !name.isEmpty else {
      print("❌ Preset: Empty name")
      return false
    }

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
