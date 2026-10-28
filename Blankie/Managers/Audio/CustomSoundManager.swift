//
//  CustomSoundManager.swift
//  Blankie
//
//  Created by Cody Bromley on 5/22/25.
//

import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import os

/// Imports, stores and retrieves custom sounds.
class CustomSoundManager {
  static let shared = CustomSoundManager()

  let customSoundsDirectory = "CustomSounds"

  /// Files at or below this size import as-is. Larger ones are still allowed but
  /// stream-transcoded to AAC on import: copying the raw bytes loads the whole
  /// file into memory, and very large uncompressed audio strains playback.
  static let maxRawImportBytes: Int64 = 150 * 1024 * 1024

  private var modelContext: ModelContext?

  private init() {
    setupCustomSoundsDirectory()
  }

  // MARK: - Setup

  @MainActor
  func setModelContext(_ context: ModelContext) {
    modelContext = context
  }

  private func setupCustomSoundsDirectory() {
    guard let directoryURL = getCustomSoundsDirectoryURL() else { return }

    if !FileManager.default.fileExists(atPath: directoryURL.path) {
      do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        Logger.sounds.debug(
          "CustomSoundManager: Created custom sounds directory at \(directoryURL.path)")
      } catch {
        Logger.sounds.error(
          "CustomSoundManager: Failed to create custom sounds directory: \(error, privacy: .public)"
        )
        ErrorReporter.shared.report(error)
      }
    }

    // Remove file protection for accessibility
    do {
      let attributes: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.none
      ]
      try FileManager.default.setAttributes(attributes, ofItemAtPath: directoryURL.path)
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Could not set file protection: \(error, privacy: .public)")
    }
  }

  // MARK: - Sound Import

  /// Copies (or transcodes) a sound file into app storage and saves its record.
  @MainActor
  func importSound(
    from sourceURL: URL, title: String, iconName: String, randomizeStartPosition: Bool = true,
    convertToAAC: Bool = false
  ) async -> Result<
    CustomSoundData, CustomSoundError
  > {
    let uniqueFileName = UUID().uuidString
    let fileExtension = sourceURL.pathExtension.lowercased()

    guard isSupportedAudioFormat(fileExtension) else {
      return .failure(CustomSoundError.unsupportedFormat)
    }

    Logger.sounds.debug("CustomSoundManager: Starting security-scoped resource access for import")
    let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        sourceURL.stopAccessingSecurityScopedResource()
        Logger.sounds.debug(
          "CustomSoundManager: Released security-scoped resource access for import")
      }
    }

    // If anything after the copy throws, remove the orphaned copy (and any
    // playback profile createCustomSoundRecord stored) so a failed import
    // leaves nothing behind. Cleared once the DB save commits.
    var copiedURLForCleanup: URL?
    defer {
      if let url = copiedURLForCleanup {
        try? FileManager.default.removeItem(at: url)
        PlaybackProfileStore.shared.removeProfile(for: uniqueFileName)
      }
    }

    do {
      try await validateImportableAudioFile(at: sourceURL)

      // Transcode when the user opted in or the file exceeds `maxRawImportBytes`.
      let sourceBytes =
        (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
      let copiedURL: URL
      let storedExtension: String
      if convertToAAC || sourceBytes > Self.maxRawImportBytes {
        guard let directoryURL = getCustomSoundsDirectoryURL() else {
          throw CustomSoundError.fileCopyFailed
        }
        let destinationURL = directoryURL.appendingPathComponent("\(uniqueFileName).m4a")
        try await Self.transcodeToAAC(source: sourceURL, destination: destinationURL)
        copiedURL = destinationURL
        storedExtension = "m4a"
        Logger.sounds.debug(
          "CustomSoundManager: import converted to AAC (\(sourceBytes) bytes, forced: \(sourceBytes > Self.maxRawImportBytes))"
        )
      } else {
        copiedURL = try copyFileForImport(
          sourceURL, uniqueFileName: uniqueFileName, fileExtension: fileExtension
        )
        storedExtension = fileExtension
      }
      copiedURLForCleanup = copiedURL
      let importData = SoundImportData(
        sourceURL: sourceURL, copiedURL: copiedURL, title: title, iconName: iconName,
        uniqueFileName: uniqueFileName, fileExtension: storedExtension,
        randomizeStartPosition: randomizeStartPosition
      )
      let customSound = try await createCustomSoundRecord(from: importData)
      try saveCustomSoundToDatabase(customSound)
      writeMirror(for: customSound)
      copiedURLForCleanup = nil

      // The keeper copy is in CustomSounds. Drop the picker's staged source
      // so it doesn't linger in tmp/Inbox (a no-op for the user's in-place files).
      removeStagedImportSource(sourceURL)

      NotificationCenter.default.post(name: .customSoundAdded, object: nil)
      return .success(customSound)
    } catch {
      Logger.sounds.error("CustomSoundManager: Failed to import sound: \(error, privacy: .public)")
      return .failure(.invalidAudioFile(error))
    }
  }

  private func validateImportableAudioFile(at sourceURL: URL) async throws {
    let validationResult = try await validateAudioFile(at: sourceURL)
    if case .failure(let error) = validationResult {
      throw (error as? CustomSoundError) ?? CustomSoundError.invalidAudioFile(error)
    }
  }

  private func copyFileForImport(_ sourceURL: URL, uniqueFileName: String, fileExtension: String)
    throws -> URL
  {
    guard
      let copiedURL = try copyToCustomSoundsDirectory(
        source: sourceURL, filename: uniqueFileName, extension: fileExtension
      )
    else {
      throw CustomSoundError.fileCopyFailed
    }
    return copiedURL
  }

  /// Builds the `CustomSoundData` record for a freshly imported file (analysis,
  /// hash, ID3, credits). Not private so the sha256/profile wiring is unit tested.
  @MainActor
  func createCustomSoundRecord(from importData: SoundImportData) async throws
    -> CustomSoundData
  {
    let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: importData.copiedURL)
    let lufsResult =
      analysis.lufs != nil
      ? (lufs: analysis.lufs!, normalizationFactor: analysis.normalizationFactor) : nil

    if let profile = PlaybackProfile.from(analysis: analysis, filename: importData.uniqueFileName) {
      PlaybackProfileStore.shared.store(profile)
      Logger.sounds.debug(
        "CustomSoundManager: Stored playback profile for \(importData.uniqueFileName)")
    }

    let metadata = await extractAudioMetadata(from: importData.copiedURL)

    let customSound = CustomSoundData(
      title: importData.title, systemIconName: importData.iconName,
      fileName: importData.uniqueFileName,
      fileExtension: importData.fileExtension,
      originalFileName: importData.sourceURL.lastPathComponent,
      randomizeStartPosition: importData.randomizeStartPosition,
      normalizeAudio: true, volumeAdjustment: 1.0, detectedPeakLevel: analysis.peakLevel,
      detectedLUFS: lufsResult?.lufs, normalizationFactor: lufsResult?.normalizationFactor,
      duration: analysis.duration
    )

    // Hash the stored file so re-importing the same audio dedupes and the mirror
    // persists a real integrity hash.
    do {
      customSound.sha256Hash = try FileHashUtility.sha256Hash(for: importData.copiedURL)
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to hash imported file for dedup: \(error, privacy: .public)")
    }

    customSound.id3Title = metadata.title
    customSound.id3Artist = metadata.artist
    customSound.id3Album = metadata.album
    customSound.id3Comment = metadata.comment
    customSound.id3Url = metadata.url

    // Seed credits from ID3 data.
    customSound.creditAuthor = metadata.artist
    customSound.creditSourceUrl = metadata.url

    return customSound
  }

  @MainActor
  private func saveCustomSoundToDatabase(_ customSound: CustomSoundData) throws {
    guard let modelContext = modelContext else {
      throw CustomSoundError.databaseError
    }
    modelContext.insert(customSound)
    try modelContext.save()
  }

  private func copyToCustomSoundsDirectory(source: URL, filename: String, extension ext: String)
    throws -> URL?
  {
    guard let directoryURL = getCustomSoundsDirectoryURL() else {
      Logger.sounds.error("CustomSoundManager: Could not get custom sounds directory URL")
      return nil
    }

    Logger.sounds.debug("CustomSoundManager: Copying from \(source.path) to CustomSounds directory")

    let destinationURL = directoryURL.appendingPathComponent("\(filename).\(ext)")
    Logger.sounds.debug("CustomSoundManager: Target destination: \(destinationURL.path)")

    do {
      guard FileManager.default.fileExists(atPath: source.path) else {
        Logger.sounds.debug("CustomSoundManager: Source file does not exist at \(source.path)")
        throw CustomSoundError.invalidAudioFile(
          NSError(
            domain: "CustomSoundManager", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Source file not found"]
          )
        )
      }

      Logger.sounds.debug("CustomSoundManager: Reading source file data...")
      let data = try Data(contentsOf: source)
      Logger.sounds.debug("CustomSoundManager: Read \(data.count) bytes from source file")

      // Atomic, so a full disk mid-write can't leave a truncated file.
      try data.write(to: destinationURL, options: .atomic)
      Logger.sounds.debug("CustomSoundManager: Successfully copied file to \(destinationURL.path)")

      if FileManager.default.fileExists(atPath: destinationURL.path) {
        Logger.sounds.debug("CustomSoundManager: Verified copied file exists at destination")
      } else {
        Logger.sounds.debug(
          "CustomSoundManager: File copy appeared successful but file not found at destination")
      }

      return destinationURL
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to copy file from \(source.path) to \(destinationURL.path): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  // MARK: - Sound Retrieval

  /// All custom sounds, oldest first.
  @MainActor
  func getAllCustomSounds() -> [CustomSoundData] {
    guard let modelContext = modelContext else {
      Logger.sounds.error("CustomSoundManager: No model context available")
      return []
    }

    do {
      let descriptor = FetchDescriptor<CustomSoundData>(sortBy: [SortDescriptor(\.dateAdded)])
      let results = try modelContext.fetch(descriptor)
      Logger.sounds.debug("CustomSoundManager: Successfully fetched \(results.count) custom sounds")
      return results
    } catch {
      Logger.sounds.error("CustomSoundManager: SwiftData fetch failed: \(error, privacy: .public)")
      Logger.sounds.debug(
        "CustomSoundManager: This indicates SwiftData container issues or actor violations")
      return []
    }
  }

  @MainActor
  func getCustomSound(by id: UUID) -> CustomSoundData? {
    guard let modelContext = modelContext else { return nil }

    let descriptor = FetchDescriptor<CustomSoundData>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try modelContext.fetch(descriptor)
      return results.first
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to fetch custom sound by ID: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - Sound Deletion

  @MainActor
  func deleteCustomSound(_ customSound: CustomSoundData) -> Result<Void, Error> {
    guard let modelContext = modelContext else {
      return .failure(CustomSoundError.databaseError)
    }

    // Capture identifiers before the object is deleted/invalidated.
    let fileName = customSound.fileName
    let fileExtension = customSound.fileExtension

    do {
      // Also remove any rendered spatial mono caches of the file.
      if let soundURL = getURLForCustomSound(customSound) {
        try FileManager.default.removeItem(at: soundURL)
        SpatialAudioCache.removeCaches(for: soundURL)
      }

      modelContext.delete(customSound)
      try modelContext.save()

      // Shared cleanup so every delete path leaves nothing behind.
      cleanUpResidualState(fileName: fileName, fileExtension: fileExtension)

      NotificationCenter.default.post(name: .customSoundDeleted, object: nil)

      return .success(())
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to delete custom sound: \(error, privacy: .public)")
      return .failure(error)
    }
  }

  /// Removes what a deleted custom sound leaves beyond its file and SwiftData row:
  /// customization, playback profile, preferences, and Quick Mix and favorite references.
  @MainActor
  private func cleanUpResidualState(fileName: String, fileExtension: String) {
    // Leave single sound or preview if this sound is the subject so neither points at a removed
    // instance. exitSingleSound() also stops playback, since there's nothing to resume.
    let audioManager = AudioManager.shared
    if audioManager.singleSound?.fileName == fileName {
      audioManager.exitSingleSound()
    }
    if audioManager.previewModeSound?.fileName == fileName {
      audioManager.exitPreviewMode()
    }

    SoundCustomizationManager.shared.removeCustomization(for: fileName)
    // Custom profiles are keyed by the bare fileName (built-ins use fileName.extension).
    PlaybackProfileStore.shared.removeProfile(for: fileName)
    // Drop the file mirror so the next launch reconcile doesn't restore the sound.
    removeMirror(fileName: fileName)

    UserDefaults.shared.removeObject(forKey: "\(fileName)_isSelected")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_volume")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_isHidden")

    let settings = GlobalSettings.shared
    if settings.quickMixSoundFileNames.contains(fileName) {
      settings.setQuickMixSoundFileNames(
        settings.quickMixSoundFileNames.filter { $0 != fileName })
    }
    let singleToken = PlayableItem.single(fileName: fileName).token
    if settings.isStarred(singleToken) {
      settings.toggleStarred(singleToken)
    }
  }

  // MARK: - Save Context

  @MainActor
  func saveContext() throws {
    try modelContext?.save()
    // Keep every sound's file mirror in step with the store after an edit save.
    syncAllMirrors()
  }

  // MARK: - Migration

  /// Backfills durations for custom sounds that lack one.
  @MainActor
  func backfillDurations() async {
    Logger.sounds.debug("CustomSoundManager: Starting duration backfill for existing custom sounds")

    guard let modelContext = modelContext else {
      Logger.sounds.error("CustomSoundManager: No model context available for backfill")
      return
    }

    do {
      let descriptor = FetchDescriptor<CustomSoundData>(
        predicate: #Predicate { $0.duration == nil }
      )
      let soundsNeedingDuration = try modelContext.fetch(descriptor)

      guard !soundsNeedingDuration.isEmpty else {
        Logger.sounds.debug("CustomSoundManager: No custom sounds need duration backfill")
        return
      }

      Logger.sounds.debug(
        "CustomSoundManager: Found \(soundsNeedingDuration.count) custom sounds needing duration")

      var successCount = 0
      var failureCount = 0

      for customSound in soundsNeedingDuration {
        guard let fileURL = getURLForCustomSound(customSound) else {
          Logger.sounds.error(
            "CustomSoundManager: Could not get URL for custom sound \(customSound.fileName, privacy: .public)"
          )
          failureCount += 1
          continue
        }

        if let duration = AudioAnalyzer.getDuration(at: fileURL) {
          customSound.duration = duration
          successCount += 1
          Logger.sounds.debug(
            "CustomSoundManager: Set duration \(String(format: "%.1f", duration))s for \(customSound.title)"
          )
        } else {
          Logger.sounds.error(
            "CustomSoundManager: Failed to calculate duration for \(customSound.fileName, privacy: .public)"
          )
          failureCount += 1
        }
      }

      if successCount > 0 {
        try modelContext.save()
        Logger.sounds.debug("CustomSoundManager: Backfilled \(successCount) durations")
      }

      if failureCount > 0 {
        Logger.sounds.error(
          "CustomSoundManager: Failed to backfill \(failureCount, privacy: .public) durations")
      }

    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Duration backfill failed: \(error, privacy: .public)")
    }
  }

  // MARK: - Internal Helper

  @MainActor
  func withModelContext<T>(_ operation: (ModelContext) throws -> T) throws -> T {
    guard let modelContext = modelContext else {
      throw CustomSoundError.databaseError
    }
    return try operation(modelContext)
  }
}

// MARK: - Errors

enum CustomSoundError: Error, LocalizedError, Sendable {
  case unsupportedFormat
  case fileCopyFailed
  case fileTooLarge
  case invalidAudioFile(Error)
  case databaseError

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      return String(
        localized:
          "Unsupported audio format. Blankie supports M4A, MP3, WAV, AIFF, FLAC, OGG, CAF, AAC, and AU files."
      )
    case .fileCopyFailed:
      return String(localized: "Failed to copy the audio file.")
    case .fileTooLarge:
      return String(localized: "Audio file is too large. Maximum size is 150MB.")
    case .invalidAudioFile(let error):
      return String(localized: "Invalid audio file: \(error.localizedDescription)")
    case .databaseError:
      return String(localized: "Failed to access the database.")
    }
  }
}

// MARK: - Notification Extensions

extension Notification.Name {
  static let customSoundAdded = Notification.Name("customSoundAdded")
  static let customSoundDeleted = Notification.Name("customSoundDeleted")
}
