//
//  CustomSoundManager+Import.swift
//  Blankie
//
//  Created by Cody Bromley on 7/12/25.
//

import Foundation
import SwiftData
import os

// MARK: - Import with Metadata

extension CustomSoundManager {
  /// Imports a sound with pre-analyzed metadata (preset imports), skipping LUFS analysis.
  @MainActor
  func importSoundWithMetadata(
    from sourceURL: URL,
    metadata: CustomSoundMetadata,
    credits: SoundCredits? = nil,
    iconOverride: String? = nil
  ) async -> Result<CustomSoundData, CustomSoundError> {
    // The metadata id doubles as the file name so preset references resolve.
    let uniqueFileName = metadata.id.uuidString
    let fileExtension = sourceURL.pathExtension.lowercased()

    Logger.sounds.debug(
      "CustomSoundManager: Importing with metadata ID: \(metadata.id) from file: \(sourceURL.lastPathComponent)"
    )

    guard isSupportedAudioFormat(fileExtension) else {
      return .failure(CustomSoundError.unsupportedFormat)
    }

    Logger.sounds.debug(
      "CustomSoundManager: Starting security-scoped resource access for import with metadata")
    let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        sourceURL.stopAccessingSecurityScopedResource()
        Logger.sounds.debug(
          "CustomSoundManager: Released security-scoped resource access for import with metadata")
      }
    }

    // If anything after the copy throws, remove the copy and its playback profile.
    // Cleared once the database save commits (as in importSound).
    var copiedURLForCleanup: URL?
    defer {
      if let url = copiedURLForCleanup {
        try? FileManager.default.removeItem(at: url)
        PlaybackProfileStore.shared.removeProfile(for: uniqueFileName)
      }
    }

    do {
      let validationResult = try await validateAudioFile(at: sourceURL)
      if case .failure(let error) = validationResult {
        throw (error as? CustomSoundError) ?? CustomSoundError.invalidAudioFile(error)
      }

      guard let directoryURL = getCustomSoundsDirectoryURL() else {
        throw CustomSoundError.fileCopyFailed
      }

      let destinationURL = directoryURL.appendingPathComponent("\(uniqueFileName).\(fileExtension)")
      let data = try Data(contentsOf: sourceURL)
      try data.write(to: destinationURL, options: .atomic)
      copiedURLForCleanup = destinationURL

      let copiedURL = destinationURL

      let customSound = createCustomSoundFromMetadata(
        metadata: metadata,
        uniqueFileName: uniqueFileName,
        fileExtension: fileExtension,
        iconOverride: iconOverride
      )

      applyCredits(to: customSound, from: credits ?? metadata.credits)

      storePlaybackProfile(for: customSound, fileName: uniqueFileName)

      await extractAndApplyID3Metadata(to: customSound, from: copiedURL)

      try withModelContext { context in
        context.insert(customSound)
        try context.save()
      }
      writeMirror(for: customSound)
      copiedURLForCleanup = nil

      NotificationCenter.default.post(name: .customSoundAdded, object: nil)
      return .success(customSound)
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to import sound with metadata: \(error, privacy: .public)")
      return .failure(.invalidAudioFile(error))
    }
  }

  private func createCustomSoundFromMetadata(
    metadata: CustomSoundMetadata,
    uniqueFileName: String,
    fileExtension: String,
    iconOverride: String?
  ) -> CustomSoundData {
    let customSound = CustomSoundData(
      title: metadata.title,
      systemIconName: iconOverride ?? metadata.systemIconName ?? "waveform.circle",
      fileName: uniqueFileName,
      fileExtension: fileExtension,
      originalFileName: metadata.originalFileName,
      randomizeStartPosition: true,
      normalizeAudio: true,
      volumeAdjustment: 1.0,
      detectedPeakLevel: nil,  // Not in metadata
      detectedLUFS: metadata.lufsValue != nil ? Float(metadata.lufsValue!) : nil,
      normalizationFactor: nil  // Will be calculated from LUFS
    )

    // Keep the original id so preset references resolve.
    customSound.id = metadata.id
    // The file is copied byte for byte, so the archive's integrity hash stays valid.
    customSound.sha256Hash = metadata.sha256Hash

    return customSound
  }

  private func applyCredits(to customSound: CustomSoundData, from credits: SoundCredits?) {
    guard let credits = credits else { return }

    customSound.creditAuthor = credits.author
    customSound.creditSourceUrl = credits.sourceUrl
    customSound.creditLicenseType = credits.license
    customSound.creditCustomLicenseText = credits.customLicenseText
    customSound.creditCustomLicenseUrl = credits.customLicenseUrl
  }

  private func storePlaybackProfile(for customSound: CustomSoundData, fileName: String) {
    guard let lufs = customSound.detectedLUFS else { return }

    // Metadata has no true peak, so use a conservative estimate.
    let estimatedTruePeak: Float = -1.0

    let profile = PlaybackProfile(
      filename: fileName,
      integratedLUFS: lufs,
      truePeakdBTP: estimatedTruePeak,
      // Floor at minimumLUFS like the analyzer, so a near-silent import stays at unity
      // gain (no full +18 dB boost).
      gainDB: lufs > AudioAnalyzer.minimumLUFS
        ? min(AudioAnalyzer.targetLUFS - lufs, AudioAnalyzer.maxGainDB)
        : 0,
      needsLimiter: lufs < -30.0  // Very quiet sounds need the limiter
    )
    PlaybackProfileStore.shared.store(profile)
    Logger.sounds.debug("CustomSoundManager: Stored playback profile from metadata for \(fileName)")
  }

  private func extractAndApplyID3Metadata(to customSound: CustomSoundData, from url: URL) async {
    let id3Metadata = await extractAudioMetadata(from: url)
    customSound.id3Title = id3Metadata.title
    customSound.id3Artist = id3Metadata.artist
    customSound.id3Album = id3Metadata.album
    customSound.id3Comment = id3Metadata.comment
    customSound.id3Url = id3Metadata.url
  }
}
