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
  /// Import a sound file with pre-analyzed metadata (used for preset imports)
  /// - Parameters:
  ///   - sourceURL: URL of the sound file to import
  ///   - metadata: Pre-analyzed metadata including LUFS values
  ///   - credits: Optional credits information
  ///   - iconOverride: Optional icon to use instead of the one in metadata
  /// - Returns: A Result with the created CustomSoundData or an error
  @MainActor
  func importSoundWithMetadata(
    from sourceURL: URL,
    metadata: CustomSoundMetadata,
    credits: SoundCredits? = nil,
    iconOverride: String? = nil
  ) async -> Result<CustomSoundData, CustomSoundError> {
    // Use the ID from metadata as the filename to maintain preset references
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

    // If anything after the copy throws, remove the orphaned copy (and its stored
    // playback profile) so a failed import leaves nothing behind. Cleared once the
    // DB save commits. Mirrors the primary importSound path.
    var copiedURLForCleanup: URL?
    defer {
      if let url = copiedURLForCleanup {
        try? FileManager.default.removeItem(at: url)
        PlaybackProfileStore.shared.removeProfile(for: uniqueFileName)
      }
    }

    do {
      // Still validate the file, but skip LUFS analysis
      let validationResult = try await validateAudioFile(at: sourceURL)
      if case .failure(let error) = validationResult {
        throw (error as? CustomSoundError) ?? CustomSoundError.invalidAudioFile(error)
      }

      // Copy the file
      guard let directoryURL = getCustomSoundsDirectoryURL() else {
        throw CustomSoundError.fileCopyFailed
      }

      let destinationURL = directoryURL.appendingPathComponent("\(uniqueFileName).\(fileExtension)")
      let data = try Data(contentsOf: sourceURL)
      try data.write(to: destinationURL, options: .atomic)
      copiedURLForCleanup = destinationURL

      let copiedURL = destinationURL

      // Create custom sound with pre-analyzed data
      let customSound = createCustomSoundFromMetadata(
        metadata: metadata,
        uniqueFileName: uniqueFileName,
        fileExtension: fileExtension,
        iconOverride: iconOverride
      )

      // Set credits if provided
      applyCredits(to: customSound, from: credits ?? metadata.credits)

      // Store playback profile if we have LUFS
      storePlaybackProfile(for: customSound, fileName: uniqueFileName)

      // Extract ID3 metadata (still useful for additional info)
      await extractAndApplyID3Metadata(to: customSound, from: copiedURL)

      // Save to database
      try withModelContext { context in
        context.insert(customSound)
        try context.save()
      }
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
      detectedPeakLevel: nil,  // We don't have peak level in metadata
      detectedLUFS: metadata.lufsValue != nil ? Float(metadata.lufsValue!) : nil,
      normalizationFactor: nil  // Will be calculated from LUFS
    )

    // CRITICAL: Preserve the original ID so preset references work
    customSound.id = metadata.id

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

    // We don't have truePeak in metadata, so use a conservative estimate
    let estimatedTruePeak: Float = -1.0  // Conservative default

    let profile = PlaybackProfile(
      filename: fileName,
      integratedLUFS: lufs,
      truePeakdBTP: estimatedTruePeak,
      gainDB: min(AudioAnalyzer.targetLUFS - lufs, AudioAnalyzer.maxGainDB),
      needsLimiter: lufs < -30.0  // Need limiter for very quiet sounds
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
