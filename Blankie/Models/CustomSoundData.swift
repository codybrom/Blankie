//
//  CustomSoundData.swift
//  Blankie
//
//  Created by Cody Bromley on 5/22/25.
//

import Foundation
import SwiftData

@Model
class CustomSoundData {
  var id = UUID()
  var title: String
  var systemIconName: String
  var fileName: String
  var fileExtension: String
  var dateAdded: Date
  var randomizeStartPosition: Bool = true
  var loopSound: Bool = true

  // Audio normalization settings
  var normalizeAudio: Bool = true
  var volumeAdjustment: Float = 1.0  // 0.5 = -50%, 1.0 = normal, 3.0 = +200%
  var detectedPeakLevel: Float?  // Legacy: Store the detected peak level for reference
  var detectedLUFS: Float?  // Store the detected LUFS (Loudness Units relative to Full Scale)
  var normalizationFactor: Float?  // Pre-calculated normalization factor

  // File integrity
  var sha256Hash: String?  // SHA-256 hash of the audio file for deduplication and integrity

  // Credit information for custom sounds
  var originalFileName: String?
  var creditAuthor: String?
  var creditSourceUrl: String?
  var creditLicenseType: String = ""
  var creditCustomLicenseText: String?
  var creditCustomLicenseUrl: String?

  // ID3 metadata extracted during import
  var id3Title: String?
  var id3Artist: String?
  var id3Album: String?
  var id3Comment: String?
  var id3Url: String?

  // Import metadata
  var importedFromPresetId: UUID?  // Which preset this sound was imported with
  var importedFromPresetName: String?  // Name of the preset it was imported with

  // Mood categorization
  var moods: [SoundMood]?  // Mood tags for categorizing custom sounds

  // Duration
  var duration: TimeInterval?  // Duration of the audio file in seconds

  init(
    title: String,
    systemIconName: String,
    fileName: String,
    fileExtension: String,
    originalFileName: String? = nil,
    randomizeStartPosition: Bool = true,
    loopSound: Bool = true,
    normalizeAudio: Bool = true,
    volumeAdjustment: Float = 1.0,
    detectedPeakLevel: Float? = nil,
    detectedLUFS: Float? = nil,
    normalizationFactor: Float? = nil,
    creditAuthor: String? = nil,
    creditSourceUrl: String? = nil,
    creditLicenseType: String = "",
    creditCustomLicenseText: String? = nil,
    creditCustomLicenseUrl: String? = nil,
    importedFromPresetId: UUID? = nil,
    importedFromPresetName: String? = nil,
    moods: [SoundMood]? = nil,
    duration: TimeInterval? = nil
  ) {
    self.title = title
    self.systemIconName = systemIconName
    self.fileName = fileName
    self.fileExtension = fileExtension
    dateAdded = Date()
    self.originalFileName = originalFileName
    self.randomizeStartPosition = randomizeStartPosition
    self.loopSound = loopSound
    self.normalizeAudio = normalizeAudio
    self.volumeAdjustment = volumeAdjustment
    self.detectedPeakLevel = detectedPeakLevel
    self.detectedLUFS = detectedLUFS
    self.normalizationFactor = normalizationFactor
    self.creditAuthor = creditAuthor
    self.creditSourceUrl = creditSourceUrl
    self.creditLicenseType = creditLicenseType
    self.creditCustomLicenseText = creditCustomLicenseText
    self.creditCustomLicenseUrl = creditCustomLicenseUrl
    self.importedFromPresetId = importedFromPresetId
    self.importedFromPresetName = importedFromPresetName
    self.moods = moods
    self.duration = duration
  }

  // Convert to SoundData for compatibility with existing system
  func toSoundData() -> SoundData {
    return SoundData(
      defaultOrder: 1000,  // Place custom sounds after built-in sounds
      title: title,
      systemIconName: systemIconName,
      fileName: fileName,
      author: "Custom Sound",
      authorUrl: nil,
      license: "Custom",
      soundUrl: "",
      soundName: originalFileName ?? fileName,
      description: nil,
      note: nil,
      lufs: detectedLUFS,
      normalizationFactor: normalizationFactor,
      moods: moods,
      duration: duration,
      truePeakdBTP: nil,  // custom sounds get true-peak/limiter from their cached PlaybackProfile
      needsLimiter: nil
    )
  }
}
