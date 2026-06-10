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

/// Manager responsible for importing, storing, and retrieving custom sounds
class CustomSoundManager {
  static let shared = CustomSoundManager()

  let customSoundsDirectory = "CustomSounds"
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

  /// Import a sound file into the app's storage and add it to the database
  /// - Parameters:
  ///   - sourceURL: URL of the sound file to import
  ///   - title: Display name for the sound
  ///   - iconName: SF Symbol name to use for the sound
  ///   - randomizeStartPosition: Whether to randomize the start position when playing
  /// - Returns: A Result with the created CustomSoundData or an error
  @MainActor
  func importSound(
    from sourceURL: URL, title: String, iconName: String, randomizeStartPosition: Bool = true
  ) async -> Result<
    CustomSoundData, CustomSoundError
  > {
    let uniqueFileName = UUID().uuidString
    let fileExtension = sourceURL.pathExtension.lowercased()

    guard isSupportedAudioFormat(fileExtension) else {
      return .failure(CustomSoundError.unsupportedFormat)
    }

    Logger.sounds.debug("CustomSoundManager: Starting security-scoped resource access for import")
    // Start security-scoped resource access at the beginning of import
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
      let copiedURL = try copyFileForImport(
        sourceURL, uniqueFileName: uniqueFileName, fileExtension: fileExtension
      )
      copiedURLForCleanup = copiedURL
      let importData = SoundImportData(
        sourceURL: sourceURL, copiedURL: copiedURL, title: title, iconName: iconName,
        uniqueFileName: uniqueFileName, fileExtension: fileExtension,
        randomizeStartPosition: randomizeStartPosition
      )
      let customSound = try await createCustomSoundRecord(from: importData)
      try saveCustomSoundToDatabase(customSound)
      copiedURLForCleanup = nil

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

  @MainActor
  private func createCustomSoundRecord(from importData: SoundImportData) async throws
    -> CustomSoundData
  {
    let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: importData.copiedURL)
    let lufsResult =
      analysis.lufs != nil
      ? (lufs: analysis.lufs!, normalizationFactor: analysis.normalizationFactor) : nil

    // Create and store playback profile for efficient runtime use
    if let profile = PlaybackProfile.from(analysis: analysis, filename: importData.uniqueFileName) {
      PlaybackProfileStore.shared.store(profile)
      Logger.sounds.debug(
        "CustomSoundManager: Stored playback profile for \(importData.uniqueFileName)")
    }

    // Extract ID3 metadata
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

    // Store ID3 metadata
    customSound.id3Title = metadata.title
    customSound.id3Artist = metadata.artist
    customSound.id3Album = metadata.album
    customSound.id3Comment = metadata.comment
    customSound.id3Url = metadata.url

    // Pre-populate credits with ID3 data if available
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
      // Check if source file exists and is accessible
      guard FileManager.default.fileExists(atPath: source.path) else {
        Logger.sounds.debug("CustomSoundManager: Source file does not exist at \(source.path)")
        throw CustomSoundError.invalidAudioFile(
          NSError(
            domain: "CustomSoundManager", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Source file not found"]
          )
        )
      }

      // Read the source file data instead of directly copying the file
      Logger.sounds.debug("CustomSoundManager: Reading source file data...")
      let data = try Data(contentsOf: source)
      Logger.sounds.debug("CustomSoundManager: Read \(data.count) bytes from source file")

      // Write to destination
      try data.write(to: destinationURL)
      Logger.sounds.debug("CustomSoundManager: Successfully copied file to \(destinationURL.path)")

      // Verify the copied file exists
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

  /// Get all custom sounds
  /// - Returns: Array of CustomSoundData objects
  @MainActor
  func getAllCustomSounds() -> [CustomSoundData] {
    guard let modelContext = modelContext else {
      Logger.sounds.error("CustomSoundManager: No model context available")
      return []
    }

    // Validate that SwiftData is ready before attempting query
    // If SwiftData hits an internal assertion (EXC_BREAKPOINT), it means the container
    // wasn't properly initialized or we have actor violations
    do {
      let descriptor = FetchDescriptor<CustomSoundData>(sortBy: [SortDescriptor(\.dateAdded)])
      let results = try modelContext.fetch(descriptor)
      Logger.sounds.debug("CustomSoundManager: Successfully fetched \(results.count) custom sounds")
      return results
    } catch {
      Logger.sounds.error("CustomSoundManager: SwiftData fetch failed: \(error, privacy: .public)")
      Logger.sounds.debug(
        "CustomSoundManager: This indicates SwiftData container issues or actor violations")
      // Return empty array to allow app to continue functioning
      return []
    }
  }

  /// Get a custom sound by its ID
  /// - Parameter id: The UUID of the custom sound
  /// - Returns: The CustomSoundData if found
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

  /// Delete a custom sound
  /// - Parameter customSound: The CustomSoundData to delete
  /// - Returns: Result indicating success or failure
  @MainActor
  func deleteCustomSound(_ customSound: CustomSoundData) -> Result<Void, Error> {
    guard let modelContext = modelContext else {
      return .failure(CustomSoundError.databaseError)
    }

    // Capture identifiers before the object is deleted/invalidated.
    let fileName = customSound.fileName
    let fileExtension = customSound.fileExtension

    do {
      // Delete the file, plus any rendered spatial mono variants of it
      if let soundURL = getURLForCustomSound(customSound) {
        try FileManager.default.removeItem(at: soundURL)
        SpatialAudioCache.removeCaches(for: soundURL)
      }

      // Delete from database
      modelContext.delete(customSound)
      try modelContext.save()

      // Centralized cleanup so every delete path (sheet, Manage Sounds, grid
      // swipe) leaves nothing behind for this sound.
      cleanUpResidualState(fileName: fileName, fileExtension: fileExtension)

      // Notify audio manager
      NotificationCenter.default.post(name: .customSoundDeleted, object: nil)

      return .success(())
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to delete custom sound: \(error, privacy: .public)")
      return .failure(error)
    }
  }

  /// Removes every trace a deleted custom sound leaves behind beyond its file
  /// and SwiftData row: its customization, playback profile, persisted per-sound
  /// preferences, and any Quick Mix / solo-favorite references. Previously these were
  /// cleaned (if at all) only on a deferred launch pass, so a deleted sound
  /// could linger in Quick Mix or as a stale CarPlay favorite until next launch.
  @MainActor
  private func cleanUpResidualState(fileName: String, fileExtension: String) {
    SoundCustomizationManager.shared.removeCustomization(for: fileName)
    // Custom profiles are keyed by the bare fileName (built-ins use
    // fileName.extension), so delete by the bare key or the profile leaks.
    PlaybackProfileStore.shared.removeProfile(for: fileName)

    UserDefaults.shared.removeObject(forKey: "\(fileName)_isSelected")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_volume")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_isHidden")

    let settings = GlobalSettings.shared
    if settings.quickMixSoundFileNames.contains(fileName) {
      settings.setQuickMixSoundFileNames(
        settings.quickMixSoundFileNames.filter { $0 != fileName })
    }
    let soloToken = "solo:\(fileName)"
    if settings.isStarred(soloToken) {
      settings.toggleStarred(soloToken)
    }
  }

  // MARK: - Save Context

  @MainActor
  func saveContext() throws {
    try modelContext?.save()
  }

  // MARK: - Migration

  /// Backfill durations for existing custom sounds that don't have duration set
  @MainActor
  func backfillDurations() async {
    Logger.sounds.debug("CustomSoundManager: Starting duration backfill for existing custom sounds")

    guard let modelContext = modelContext else {
      Logger.sounds.error("CustomSoundManager: No model context available for backfill")
      return
    }

    do {
      // Fetch all custom sounds that don't have duration set
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

        // Calculate duration
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

      // Save changes
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
  case durationTooLong
  case invalidAudioFile(Error)
  case databaseError

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      return "Unsupported audio format. Please use WAV, MP3, M4A, AAC, or AIFF files."
    case .fileCopyFailed:
      return "Failed to copy the audio file."
    case .fileTooLarge:
      return "Audio file is too large. Maximum size is 50MB."
    case .durationTooLong:
      return "Audio file is too long. Maximum duration is 120 minutes."
    case .invalidAudioFile(let error):
      return "Invalid audio file: \(error.localizedDescription)"
    case .databaseError:
      return "Failed to access the database."
    }
  }
}

// MARK: - Notification Extensions

extension Notification.Name {
  static let customSoundAdded = Notification.Name("customSoundAdded")
  static let customSoundDeleted = Notification.Name("customSoundDeleted")
}
