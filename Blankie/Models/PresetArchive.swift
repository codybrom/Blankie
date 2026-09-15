//
//  PresetArchive.swift
//  Blankie
//
//  Created by Cody Bromley on 6/25/25.
//

import Foundation

// MARK: - Archive Models

nonisolated struct PresetArchive: Codable {
  let manifest: ArchiveManifest
  let preset: Preset
  let customSounds: [CustomSoundMetadata]

  var archiveName: String {
    return "\(preset.name).blankie"
  }
}

nonisolated struct SoundsManifest: Codable {
  let customSounds: [CustomSoundMetadata]
  let builtInCustomizations: [SoundCustomization]
}

nonisolated struct ArchiveManifest: Codable {
  let version: String
  let blankieVersion: String
  let createdDate: Date
  let compatibility: ArchiveCompatibility

  init(blankieVersion: String) {
    version = "1.0"
    self.blankieVersion = blankieVersion
    createdDate = Date()
    compatibility = ArchiveCompatibility()
  }
}

nonisolated struct ArchiveCompatibility: Codable {
  let minimumBlankieVersion: String
  let requiredFeatures: [String]

  init() {
    minimumBlankieVersion = "2.0.0"
    requiredFeatures = []
  }

  func isCompatible(with currentVersion: String) -> Bool {
    // Numeric comparison so multi-digit version segments order correctly
    // (e.g. "1.10.0" > "1.9.0"); plain String >= is lexicographic.
    return currentVersion.compare(minimumBlankieVersion, options: .numeric) != .orderedAscending
  }
}

nonisolated struct CustomSoundMetadata: Codable, Identifiable {
  let id: UUID
  let fileName: String
  let originalFileName: String
  let title: String
  let systemIconName: String?  // Made optional for backwards compatibility
  let lufsValue: Double?
  let sha256Hash: String?
  let credits: SoundCredits?

  @MainActor init(from customSoundData: CustomSoundData) {
    id = customSoundData.id
    // Use the existing fileName to match what Sound objects reference
    fileName = "\(customSoundData.fileName).\(customSoundData.fileExtension)"
    originalFileName = customSoundData.originalFileName ?? customSoundData.fileName
    title = customSoundData.title
    systemIconName = customSoundData.systemIconName
    lufsValue =
      customSoundData.detectedLUFS != nil ? Double(customSoundData.detectedLUFS!) : nil
    sha256Hash = customSoundData.sha256Hash

    // Create credits from custom sound data
    var credits: SoundCredits?
    if customSoundData.creditAuthor != nil || customSoundData.creditSourceUrl != nil {
      credits = SoundCredits(
        soundName: customSoundData.originalFileName ?? customSoundData.title,
        author: customSoundData.creditAuthor ?? "",
        sourceUrl: customSoundData.creditSourceUrl,
        license: customSoundData.creditLicenseType,
        customLicenseText: customSoundData.creditCustomLicenseText,
        customLicenseUrl: customSoundData.creditCustomLicenseUrl
      )
    }
    self.credits = credits
  }
}

nonisolated struct SoundCredits: Codable {
  let soundName: String
  let author: String
  let sourceUrl: String?
  let license: String
  let customLicenseText: String?
  let customLicenseUrl: String?
}

// MARK: - Archive File Paths

extension PresetArchive {
  nonisolated static let manifestFileName = "manifest.json"
  nonisolated static let presetFileName = "preset.json"
  nonisolated static let soundsDirectoryName = "sounds"
  nonisolated static let soundsMetadataFileName = "metadata.json"
  nonisolated static let artworkFileName = "artwork.jpg"
  nonisolated static let backgroundFileName = "background.jpg"
  nonisolated static let animatedLoopBaseName = "animatedLoop"
  nonisolated static let animatedPreviewFileName = "animatedPreview.jpg"

  func soundFileName(for customSoundId: UUID) -> String {
    guard let sound = customSounds.first(where: { $0.id == customSoundId }) else {
      return "\(customSoundId.uuidString).m4a"
    }
    return sound.fileName
  }
}
