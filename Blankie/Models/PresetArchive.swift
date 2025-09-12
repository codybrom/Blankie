//
//  PresetArchive.swift
//  Blankie
//
//  Created by Cody Bromley on 6/25/25.
//

import Foundation

// MARK: - Archive Models

struct PresetArchive: Codable {
  let manifest: ArchiveManifest
  let preset: Preset
  let customSounds: [CustomSoundMetadata]

  var archiveName: String {
    return "\(preset.name).blankie"
  }
}

struct SoundsManifest: Codable {
  let customSounds: [CustomSoundMetadata]
  let builtInCustomizations: [SoundCustomization]
}

struct ArchiveManifest: Codable {
  let version: String
  let blankieVersion: String
  let createdDate: Date
  let compatibility: ArchiveCompatibility

  init(blankieVersion: String) {
    self.version = "1.0"
    self.blankieVersion = blankieVersion
    self.createdDate = Date()
    self.compatibility = ArchiveCompatibility()
  }
}

struct ArchiveCompatibility: Codable {
  let minimumBlankieVersion: String
  let requiredFeatures: [String]

  init() {
    self.minimumBlankieVersion = "1.1.0"
    self.requiredFeatures = []
  }

  func isCompatible(with currentVersion: String) -> Bool {
    // Simple version comparison - in production would use proper version parsing
    return currentVersion >= minimumBlankieVersion
  }
}

struct CustomSoundMetadata: Codable, Identifiable {
  let id: UUID
  let fileName: String
  let originalFileName: String
  let title: String
  let systemIconName: String?  // Made optional for backwards compatibility
  let lufsValue: Double?
  let sha256Hash: String?
  let credits: SoundCredits?

  init(from customSoundData: CustomSoundData) {
    self.id = customSoundData.id
    // Use the existing fileName to match what Sound objects reference
    self.fileName = "\(customSoundData.fileName).\(customSoundData.fileExtension)"
    self.originalFileName = customSoundData.originalFileName ?? customSoundData.fileName
    self.title = customSoundData.title
    self.systemIconName = customSoundData.systemIconName
    self.lufsValue =
      customSoundData.detectedLUFS != nil ? Double(customSoundData.detectedLUFS!) : nil
    self.sha256Hash = customSoundData.sha256Hash

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

struct SoundCredits: Codable {
  let soundName: String
  let author: String
  let sourceUrl: String?
  let license: String
  let customLicenseText: String?
  let customLicenseUrl: String?
}

// MARK: - Archive File Paths

extension PresetArchive {
  static let manifestFileName = "manifest.json"
  static let presetFileName = "preset.json"
  static let soundsDirectoryName = "sounds"
  static let soundsMetadataFileName = "metadata.json"
  static let artworkFileName = "artwork.jpg"
  static let backgroundFileName = "background.jpg"

  func soundFileName(for customSoundId: UUID) -> String {
    guard let sound = customSounds.first(where: { $0.id == customSoundId }) else {
      return "\(customSoundId.uuidString).m4a"
    }
    return sound.fileName
  }
}
