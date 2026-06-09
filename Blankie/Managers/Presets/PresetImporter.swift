//
//  PresetImporter.swift
//  Blankie
//
//  Created by Cody Bromley on 6/25/25.
//

import Foundation
import SwiftUI
import os

// MARK: - Duplicate Detection Helper

private enum DuplicateDetectionHelper {
  static func checkForDuplicatePreset(_ preset: Preset) async -> Preset? {
    await MainActor.run {
      let existingPresets = PresetManager.shared.presets

      // Check if we've already imported this exact preset (by original ID)
      if let duplicate = existingPresets.first(where: { $0.originalId == preset.id }) {
        Logger.presets.debug(
          "Import: Found previously imported preset with original ID \(preset.id)")
        return duplicate
      }

      // Check for same name to avoid confusion
      if let sameName = existingPresets.first(where: { $0.name == preset.name }) {
        Logger.presets.debug("Import: Found existing preset with same name '\(preset.name)'")
        return sameName
      }

      return nil
    }
  }

  static func generateUniquePresetName(baseName: String) async -> String {
    await MainActor.run {
      let existingPresets = PresetManager.shared.presets
      let existingNames = Set(existingPresets.map(\.name))

      // If the base name is unique, use it
      if !existingNames.contains(baseName) {
        return baseName
      }

      // Find the next available number
      var counter = 2
      while true {
        let candidateName = "\(baseName) (\(counter))"
        if !existingNames.contains(candidateName) {
          Logger.presets.debug("Import: Generated unique name '\(candidateName)'")
          return candidateName
        }
        counter += 1
      }
    }
  }

  struct ExistingSoundInfo {
    let id: UUID
    let sha256Hash: String?
  }

  static func checkIfSoundExists(_ soundMetadata: CustomSoundMetadata) async -> ExistingSoundInfo? {
    await MainActor.run {
      // Check if a custom sound with the same ID already exists
      let customSoundManager = CustomSoundManager.shared
      let existingSounds = customSoundManager.getAllCustomSounds()

      // Check by original ID first (most reliable)
      if let existingSound = existingSounds.first(where: { $0.id == soundMetadata.id }) {
        return ExistingSoundInfo(id: existingSound.id, sha256Hash: existingSound.sha256Hash)
      }

      // Also check by original filename as backup (in case IDs changed)
      if let existingByFilename = existingSounds.first(where: { existing in
        existing.originalFileName == soundMetadata.originalFileName
          && existing.title == soundMetadata.title
      }) {
        return ExistingSoundInfo(
          id: existingByFilename.id, sha256Hash: existingByFilename.sha256Hash
        )
      }

      return nil
    }
  }
}

// MARK: - Sound Customization Helper

private enum SoundCustomizationImporter {
  static func importFromManifest(from archiveURL: URL) async throws {
    let soundsDir = archiveURL.appendingPathComponent(PresetArchive.soundsDirectoryName)
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)

    // Check if metadata file exists
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      Logger.presets.debug("Import: No sound metadata found in archive")
      return
    }

    do {
      let metadataData = try Data(contentsOf: metadataURL)

      let soundsManifest = try JSONDecoder().decode(SoundsManifest.self, from: metadataData)
      let customizations = soundsManifest.builtInCustomizations
      await applyCustomizations(customizations)
    } catch {
      Logger.presets.error(
        "Import: Failed to import sound customizations: \(error, privacy: .public)")
      // Don't throw error - customizations are optional
    }
  }

  private static func applyCustomizations(_ customizations: [SoundCustomization]) async {
    guard !customizations.isEmpty else {
      Logger.presets.debug("Import: No sound customizations to apply")
      return
    }

    await MainActor.run {
      let customizationManager = SoundCustomizationManager.shared
      var appliedCount = 0
      var skippedCount = 0

      for customization in customizations {
        // Check if this sound already has customizations - if so, skip to preserve user's settings
        if customizationManager.getCustomization(for: customization.fileName) != nil {
          skippedCount += 1
          continue
        }

        // Apply each customization property if it's not nil
        if let title = customization.customTitle {
          customizationManager.setCustomTitle(title, for: customization.fileName)
        }
        if let iconName = customization.customIconName {
          customizationManager.setCustomIcon(iconName, for: customization.fileName)
        }
        if let randomizeStart = customization.randomizeStartPosition {
          customizationManager.setRandomizeStartPosition(
            randomizeStart, for: customization.fileName
          )
        }
        if let normalizeAudio = customization.normalizeAudio {
          customizationManager.setNormalizeAudio(normalizeAudio, for: customization.fileName)
        }
        if let volumeAdjustment = customization.volumeAdjustment {
          customizationManager.setVolumeAdjustment(volumeAdjustment, for: customization.fileName)
        }
        if let loopSound = customization.loopSound {
          customizationManager.setLoopSound(loopSound, for: customization.fileName)
        }

        appliedCount += 1
      }

      Logger.presets.debug(
        "Import: Applied \(appliedCount) sound customizations, skipped \(skippedCount) existing")
    }
  }
}

class PresetImporter {
  static let shared = PresetImporter()

  private init() {}

  // Type aliases for helper structs
  fileprivate typealias ExistingSoundInfo = DuplicateDetectionHelper.ExistingSoundInfo

  enum ImportError: LocalizedError {
    case invalidArchive
    case incompatibleVersion
    case missingRequiredFiles
    case corruptedData
    case sharingRestricted
    case soundImportFailed(String)

    var errorDescription: String? {
      switch self {
      case .invalidArchive:
        return "Invalid .blankie file"
      case .incompatibleVersion:
        return "This preset requires a newer version of Blankie"
      case .missingRequiredFiles:
        return "Missing required files in preset archive"
      case .corruptedData:
        return "Preset data is corrupted"
      case .sharingRestricted:
        return "This preset cannot be modified due to sharing restrictions"
      case .soundImportFailed(let soundName):
        return "Failed to import custom sound: \(soundName)"
      }
    }
  }

  // MARK: - Import Logic

  func importArchive(from url: URL) async throws -> Preset {
    // Ensure we have access to the security-scoped resource
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    // Extract archive
    let (archiveURL, tempExtractedURL) = try extractArchive(from: url)

    defer {
      // Clean up temporary files
      if let tempURL = tempExtractedURL {
        try? FileManager.default.removeItem(at: tempURL)
        Logger.presets.debug("Import: Cleaned up extracted files at \(tempURL.lastPathComponent)")
      }
      // Clean up the imported file if it's in the tmp directory
      if url.path.contains("/tmp/") {
        try? FileManager.default.removeItem(at: url)
        Logger.presets.debug("Import: Cleaned up temporary file at \(url.lastPathComponent)")
      }
    }

    try validateArchiveStructure(at: archiveURL)

    let manifest = try await readManifest(from: archiveURL)
    try validateCompatibility(manifest)

    var preset = try await readPreset(from: archiveURL)

    if await DuplicateDetectionHelper.checkForDuplicatePreset(preset) != nil {
      Logger.presets.debug("Import: Found existing preset with ID \(preset.id)")
      preset.name = await DuplicateDetectionHelper.generateUniquePresetName(baseName: preset.name)
    }

    try await importArtwork(for: &preset, from: archiveURL)

    let idMapping = try await importCustomSounds(for: preset, from: archiveURL)
    try await SoundCustomizationImporter.importFromManifest(from: archiveURL)

    // Imported custom sounds get fresh IDs, so remap the preset's sound states
    if !idMapping.isEmpty {
      preset = updatePresetSoundStates(preset, with: idMapping)
    }

    // Re-ID the preset so it can't collide with an existing one
    preset = createNewPresetInstance(from: preset)

    await addAndActivatePreset(preset)

    return preset
  }

  private func extractArchive(from url: URL) throws -> (
    archiveURL: URL, tempExtractedURL: URL?
  ) {
    var archiveURL = url
    var tempExtractedURL: URL?

    // If it's a file (not a directory), we need to extract it
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    {
      Logger.presets.debug("Import: Detected compressed .blankie file, extracting...")

      // Create a temporary directory for extraction
      let tempDir = FileManager.default.temporaryDirectory
      let extractionDir = tempDir.appendingPathComponent("blankie-import-\(UUID().uuidString)")

      do {
        // Create extraction directory
        try FileManager.default.createDirectory(
          at: extractionDir, withIntermediateDirectories: true
        )

        try ArchiveUtility.extract(from: url, to: extractionDir)

        archiveURL = extractionDir
        tempExtractedURL = extractionDir
        Logger.presets.debug("Import: Successfully extracted to \(extractionDir.lastPathComponent)")

      } catch {
        Logger.presets.error("Import: Failed to extract archive: \(error, privacy: .public)")
        throw ImportError.invalidArchive
      }
    }

    return (archiveURL, tempExtractedURL)
  }
}

// MARK: - CustomSoundMetadata Extension

extension CustomSoundMetadata {
  init(
    id: UUID,
    fileName: String,
    originalFileName: String,
    title: String,
    systemIconName: String?,
    lufsValue: Double?,
    sha256Hash: String?,
    credits: SoundCredits?
  ) {
    self.id = id
    self.fileName = fileName
    self.originalFileName = originalFileName
    self.title = title
    self.systemIconName = systemIconName
    self.lufsValue = lufsValue
    self.sha256Hash = sha256Hash
    self.credits = credits
  }
}

// MARK: - Sound Import Extension

extension PresetImporter {
  @MainActor
  func importCustomSounds(
    for preset: Preset, from archiveURL: URL
  ) async throws -> [UUID: UUID] {
    let soundsDir = archiveURL.appendingPathComponent(PresetArchive.soundsDirectoryName)

    guard FileManager.default.fileExists(atPath: soundsDir.path) else {
      return [:]  // No custom sounds to import
    }

    // Read sounds metadata and customizations
    let customSounds = try readSoundsMetadata(from: soundsDir)
    guard !customSounds.isEmpty else {
      return [:]
    }

    // Also read customizations to get icon info
    let customizations = try readCustomizations(from: soundsDir)

    // Import each custom sound
    var importedCount = 0
    var idMapping: [UUID: UUID] = [:]  // Maps original IDs to actual IDs (existing or new)

    for soundMetadata in customSounds {
      // Process existing sound if found
      if let existingSound = await DuplicateDetectionHelper.checkIfSoundExists(soundMetadata) {
        if let mappedId = await processExistingSound(
          soundMetadata, existingSound, &importedCount
        ) {
          idMapping[soundMetadata.id] = mappedId
          continue
        }
      }

      // Import new sound. Reduce the manifest-supplied fileName to its final
      // component so a crafted "../.." path can't read a file outside soundsDir.
      let safeFileName = (soundMetadata.fileName as NSString).lastPathComponent
      let soundFileURL = soundsDir.appendingPathComponent(safeFileName)
      let importedId = try await importNewSound(
        soundMetadata, soundFileURL, preset, &importedCount, customizations: customizations
      )
      idMapping[soundMetadata.id] = importedId
    }

    return idMapping
  }

  private func readSoundsMetadata(from soundsDir: URL) throws -> [CustomSoundMetadata] {
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      return []
    }

    let metadataData = try Data(contentsOf: metadataURL)
    let soundsManifest = try JSONDecoder().decode(SoundsManifest.self, from: metadataData)
    return soundsManifest.customSounds
  }

  private func readCustomizations(from soundsDir: URL) throws -> [SoundCustomization] {
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      return []
    }

    do {
      let metadataData = try Data(contentsOf: metadataURL)
      let soundsManifest = try JSONDecoder().decode(SoundsManifest.self, from: metadataData)
      return soundsManifest.builtInCustomizations
    } catch {
      // Return empty array if no customizations found
      return []
    }
  }

  @MainActor
  private func processExistingSound(
    _ soundMetadata: CustomSoundMetadata,
    _ existingSound: ExistingSoundInfo,
    _ importedCount: inout Int
  ) async -> UUID? {
    Logger.presets.debug(
      "Import: Sound '\(soundMetadata.title)' already exists with ID \(existingSound.id)")

    // If we have SHA hashes, verify they match
    if let existingHash = existingSound.sha256Hash,
      let importHash = soundMetadata.sha256Hash,
      existingHash != importHash
    {
      Logger.presets.debug(
        "Import: SHA hash mismatch for '\(soundMetadata.title)' - treating as different file")
      return nil  // Continue with import as it's a different file
    }

    // Same file, skip import but record the ID mapping
    Logger.presets.debug("Import: SHA hash matches or not available - skipping duplicate import")
    importedCount += 1
    return existingSound.id
  }

  @MainActor
  private func importNewSound(
    _ soundMetadata: CustomSoundMetadata,
    _ soundFileURL: URL,
    _: Preset,
    _ importedCount: inout Int,
    customizations: [SoundCustomization] = []
  ) async throws -> UUID {
    guard FileManager.default.fileExists(atPath: soundFileURL.path) else {
      throw ImportError.soundImportFailed(soundMetadata.title)
    }

    // Extract the UUID from the filename if it's different from metadata ID
    let fileNameWithoutExt = (soundFileURL.lastPathComponent as NSString).deletingPathExtension
    let actualId: UUID
    if let uuidFromFilename = UUID(uuidString: fileNameWithoutExt),
      uuidFromFilename != soundMetadata.id
    {
      Logger.presets.debug(
        "PresetImporter: Filename UUID \(uuidFromFilename) differs from metadata ID \(soundMetadata.id), using filename UUID"
      )
      actualId = uuidFromFilename
    } else {
      actualId = soundMetadata.id
    }

    do {
      // Find icon from customizations if available
      let fileNameWithoutExtension = (soundMetadata.fileName as NSString).deletingPathExtension
      let iconFromCustomization = customizations.first(where: {
        $0.fileName == fileNameWithoutExtension
      })?.customIconName

      // Create a modified metadata with the correct ID
      let correctedMetadata = CustomSoundMetadata(
        id: actualId,
        fileName: soundMetadata.fileName,
        originalFileName: soundMetadata.originalFileName,
        title: soundMetadata.title,
        systemIconName: soundMetadata.systemIconName,
        lufsValue: soundMetadata.lufsValue,
        sha256Hash: soundMetadata.sha256Hash,
        credits: soundMetadata.credits
      )

      // Use the new import method that doesn't re-analyze LUFS
      let result = await CustomSoundManager.shared.importSoundWithMetadata(
        from: soundFileURL,
        metadata: correctedMetadata,
        credits: soundMetadata.credits,
        iconOverride: iconFromCustomization
      )

      switch result {
      case .success:
        break
      case .failure(let error):
        Logger.presets.error("PresetImporter: Failed to import sound: \(error, privacy: .public)")
        throw ImportError.soundImportFailed(soundMetadata.title)
      }

      // Update progress
      importedCount += 1

      return actualId  // Return the actual ID we used

    } catch {
      throw ImportError.soundImportFailed(soundMetadata.title)
    }
  }

  private func createCustomSoundData(
    from soundMetadata: CustomSoundMetadata, preset: Preset,
    customizations: [SoundCustomization] = []
  )
    -> CustomSoundData
  {
    // Extract file info from metadata
    let fileNameWithoutExtension = (soundMetadata.fileName as NSString).deletingPathExtension
    let fileExtension = (soundMetadata.fileName as NSString).pathExtension

    // Try to find icon from customizations first
    let iconName =
      customizations.first(where: { $0.fileName == fileNameWithoutExtension })?.customIconName
      ?? soundMetadata.systemIconName
      ?? "waveform.circle"  // Default icon for older imports

    // Create CustomSoundData from metadata - PRESERVING THE ORIGINAL ID
    let customSoundData = CustomSoundData(
      title: soundMetadata.title,
      systemIconName: iconName,
      fileName: fileNameWithoutExtension,
      fileExtension: fileExtension,
      originalFileName: soundMetadata.originalFileName,
      detectedLUFS: soundMetadata.lufsValue != nil ? Float(soundMetadata.lufsValue!) : nil,
      creditAuthor: soundMetadata.credits?.author,
      creditSourceUrl: soundMetadata.credits?.sourceUrl,
      creditLicenseType: soundMetadata.credits?.license ?? "",
      creditCustomLicenseText: soundMetadata.credits?.customLicenseText,
      creditCustomLicenseUrl: soundMetadata.credits?.customLicenseUrl,
      importedFromPresetId: preset.id,
      importedFromPresetName: preset.name
    )

    // Preserve the original ID and SHA hash so presets can share sounds
    customSoundData.id = soundMetadata.id
    customSoundData.sha256Hash = soundMetadata.sha256Hash

    return customSoundData
  }
}

// MARK: - Processing & Updates Extension

extension PresetImporter {
  func importArtwork(for preset: inout Preset, from archiveURL: URL) async throws {
    try await importStaticArtwork(for: &preset, from: archiveURL)
    try await importAnimatedArtwork(for: &preset, from: archiveURL)
  }

  private func importStaticArtwork(for preset: inout Preset, from archiveURL: URL) async throws {
    let artworkURL = archiveURL.appendingPathComponent(PresetArchive.artworkFileName)
    guard FileManager.default.fileExists(atPath: artworkURL.path),
      let artworkData = try? Data(contentsOf: artworkURL)
    else {
      return
    }

    let artworkId = try await PresetArtworkManager.shared.saveArtwork(
      artworkData, for: preset.id, type: .artwork
    )
    preset.artworkId = artworkId

    // Ensure static artwork path mirrors the exported image
    let staticId = UUID()
    let staticRel = AnimatedArtworkFileStore.makeRelativePreviewPath(for: staticId)
    _ = try? AnimatedArtworkFileStore.writeData(artworkData, to: staticRel)
    preset.staticArtworkPath = staticRel
  }

  private func importAnimatedArtwork(for preset: inout Preset, from archiveURL: URL) async throws {
    if let animated = preset.animatedArtwork {
      if animated.source == .bundled, let bundledId = animated.bundledIdentifier {
        try importBundledAnimation(bundledId: bundledId, animated: animated, for: &preset)
      } else if let loopSource = findAnimatedLoop(in: archiveURL) {
        try importCustomAnimation(
          loopSource: loopSource, animated: animated, for: &preset, from: archiveURL)
      }
    } else if let loopSource = findAnimatedLoop(in: archiveURL) {
      try importLegacyAnimation(loopSource: loopSource, for: &preset, from: archiveURL)
    }
  }

  private func importBundledAnimation(
    bundledId: String, animated: AnimatedArtworkRef, for preset: inout Preset
  ) throws {
    Logger.presets.debug("Import: Restoring bundled animation '\(bundledId)' from app bundle")

    // Capture the preset ID to look it up later
    let presetId = preset.id

    // Schedule the ODR download asynchronously - don't block import
    Task { @MainActor in
      do {
        // Request the video file from ODR (downloads if needed)
        let videoURL = try await OnDemandResourceManager.shared.requestVideoResource(bundledId)
        Logger.presets.debug("Import: Successfully downloaded ODR resource '\(bundledId)'")

        // Get preview images from bundle (these are always available, not part of ODR)
        guard
          let previewURL = Bundle.main.url(
            forResource: "\(bundledId)/\(bundledId)", withExtension: "jpg"),
          let squarePreviewURL = Bundle.main.url(
            forResource: "\(bundledId)/\(bundledId)Square", withExtension: "jpg")
        else {
          Logger.presets.error(
            "Import: Failed to find preview images for '\(bundledId, privacy: .public)'")
          return
        }

        // Copy files to Documents
        let assetId = UUID()
        let loopRel = AnimatedArtworkFileStore.makeRelativeLoopPath(
          for: assetId, fileExtension: "mov")
        let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: "jpg")
        let squarePreviewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: "jpg", suffix: "Square")

        _ = try? AnimatedArtworkFileStore.copyItem(at: videoURL, to: loopRel)
        _ = try? AnimatedArtworkFileStore.copyItem(at: previewURL, to: previewRel)
        _ = try? AnimatedArtworkFileStore.copyItem(at: squarePreviewURL, to: squarePreviewRel)

        // Update the preset's animated artwork reference
        var updatedAnimated = animated
        updatedAnimated.loopPath = loopRel
        updatedAnimated.previewPath = previewRel
        updatedAnimated.squarePreviewPath = squarePreviewRel

        // Update the preset in PresetManager using the captured preset ID
        if let index = PresetManager.shared.presets.firstIndex(where: { $0.id == presetId }) {
          var updatedPreset = PresetManager.shared.presets[index]
          updatedPreset.animatedArtwork = updatedAnimated
          PresetManager.shared.updatePresetAtIndex(index, with: updatedPreset)
          PresetManager.shared.savePresets()
          Logger.presets.debug("Import: Successfully restored bundled animation '\(bundledId)'")
        }

      } catch {
        Logger.presets.error(
          "Import: Failed to download ODR resource '\(bundledId, privacy: .public)': \(error, privacy: .public)"
        )
        // Don't throw - preset can still be used without animated artwork
      }
    }

    // Set up the animated artwork reference with the bundled identifier
    // The actual files will be downloaded and copied asynchronously
    var updatedAnimated = animated
    updatedAnimated.bundledIdentifier = bundledId
    preset.animatedArtwork = updatedAnimated

    Logger.presets.debug("Import: Scheduled download for bundled animation '\(bundledId)'")
  }

  private func importCustomAnimation(
    loopSource: URL, animated: AnimatedArtworkRef, for preset: inout Preset, from archiveURL: URL
  ) throws {
    let assetId = UUID()
    let loopRel = AnimatedArtworkFileStore.makeRelativeLoopPath(
      for: assetId,
      fileExtension: loopSource.pathExtension.isEmpty ? "mov" : loopSource.pathExtension
    )
    _ = try AnimatedArtworkFileStore.copyItem(at: loopSource, to: loopRel)

    let previewRel = importAnimatedPreview(
      assetId: assetId, from: archiveURL, staticPath: preset.staticArtworkPath)

    var animatedRef = animated
    animatedRef.loopPath = loopRel
    animatedRef.previewPath = previewRel
    animatedRef.preferredAspect = animatedRef.preferredAspect ?? "3x4"
    preset.animatedArtwork = animatedRef

    if let previewRel {
      preset.staticArtworkPath = previewRel
    }
  }

  private func importLegacyAnimation(
    loopSource: URL, for preset: inout Preset, from archiveURL: URL
  ) throws {
    let assetId = UUID()
    let loopRel = AnimatedArtworkFileStore.makeRelativeLoopPath(
      for: assetId,
      fileExtension: loopSource.pathExtension.isEmpty ? "mov" : loopSource.pathExtension
    )
    _ = try AnimatedArtworkFileStore.copyItem(at: loopSource, to: loopRel)

    let previewRel = importAnimatedPreview(
      assetId: assetId, from: archiveURL, staticPath: preset.staticArtworkPath)

    preset.animatedArtwork = AnimatedArtworkRef(
      source: .custom,
      loopPath: loopRel,
      previewPath: previewRel,
      preferredAspect: "3x4"
    )

    if let previewRel {
      preset.staticArtworkPath = previewRel
    }
  }

  private func importAnimatedPreview(assetId: UUID, from archiveURL: URL, staticPath: String?)
    -> String?
  {
    let previewSource = archiveURL.appendingPathComponent(PresetArchive.animatedPreviewFileName)
    if FileManager.default.fileExists(atPath: previewSource.path) {
      let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(for: assetId)
      _ = try? AnimatedArtworkFileStore.copyItem(at: previewSource, to: previewRel)
      return previewRel
    } else if let staticPath, AnimatedArtworkFileStore.fileExists(at: staticPath) {
      return staticPath
    }
    return nil
  }

  private func findAnimatedLoop(in directory: URL) -> URL? {
    let fileManager = FileManager.default
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      )
    else {
      return nil
    }

    return contents.first { url in
      guard url.hasDirectoryPath == false else { return false }
      let fileName = url.deletingPathExtension().lastPathComponent
      return fileName == PresetArchive.animatedLoopBaseName
    }
  }

  func updatePresetSoundStates(_ preset: Preset, with idMapping: [UUID: UUID]) -> Preset {
    var updatedPreset = preset

    // Update sound states to use the correct IDs
    updatedPreset.soundStates = preset.soundStates.map { state in
      // Check if this is a custom sound by looking for its ID in the mapping
      // The fileName for custom sounds is typically the UUID string
      if let soundId = UUID(uuidString: state.fileName),
        let mappedId = idMapping[soundId]
      {
        // Create a new PresetState with the mapped ID
        let updatedState = PresetState(
          fileName: mappedId.uuidString,
          isSelected: state.isSelected,
          volume: state.volume
        )
        Logger.presets.debug(
          "Import: Updated sound state from \(state.fileName) to \(mappedId.uuidString)")
        return updatedState
      }

      // Not a custom sound or not in mapping, keep as is
      return state
    }

    return updatedPreset
  }

  func createNewPresetInstance(from preset: Preset) -> Preset {
    // Create a new preset with a new ID to avoid conflicts
    let newPreset = Preset(
      id: UUID(),  // Generate new ID
      name: preset.name,
      soundStates: preset.soundStates,
      isDefault: false,
      createdVersion: preset.createdVersion,
      lastModifiedVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "2.0.0",
      soundOrder: preset.soundOrder,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId,
      animatedArtwork: preset.animatedArtwork,
      staticArtworkPath: preset.staticArtworkPath,
      order: preset.order,
      isImported: true,  // Mark as imported
      originalId: preset.id,  // Store the original ID for duplicate detection
      // Carry the theme through import so shared presets keep their look.
      moods: preset.moods,
      accentColorName: preset.accentColorName,
      viewMode: preset.viewMode,
      backgroundBlurRadius: preset.backgroundBlurRadius
    )

    return newPreset
  }

  func addAndActivatePreset(_ preset: Preset) async {
    await MainActor.run {
      let presetManager = PresetManager.shared
      let audioManager = AudioManager.shared

      // Only load the custom sounds that are in this preset
      let customSoundIds = preset.soundStates
        .compactMap { state -> UUID? in
          // Check if the fileName is a UUID (custom sound)
          return UUID(uuidString: state.fileName)
        }

      if !customSoundIds.isEmpty {
        audioManager.loadCustomSoundsByIds(Set(customSoundIds))
      }

      // Add to presets
      var currentPresets = presetManager.presets
      currentPresets.append(preset)
      presetManager.setPresets(currentPresets)

      // Cache thumbnail for CarPlay if artwork exists
      if preset.artworkId != nil {
        Task {
          await presetManager.cacheThumbnail(for: preset)
        }
      }

      // Save presets to persist the import
      presetManager.savePresets()

      // Activate the imported preset immediately
      do {
        try presetManager.applyPreset(preset)
      } catch {
        Logger.presets.error("Import: Failed to apply preset: \(error, privacy: .public)")
      }

      Logger.presets.debug("Import: Successfully imported and activated preset '\(preset.name)'")
    }
  }
}

// MARK: - Validation Extension

extension PresetImporter {
  func validateArchiveStructure(at url: URL) throws {
    let manifestURL = url.appendingPathComponent(PresetArchive.manifestFileName)
    let presetURL = url.appendingPathComponent(PresetArchive.presetFileName)

    guard FileManager.default.fileExists(atPath: manifestURL.path),
      FileManager.default.fileExists(atPath: presetURL.path)
    else {
      throw ImportError.missingRequiredFiles
    }
  }

  func readManifest(from archiveURL: URL) async throws -> ArchiveManifest {
    let manifestURL = archiveURL.appendingPathComponent(PresetArchive.manifestFileName)
    let manifestData = try Data(contentsOf: manifestURL)
    return try JSONDecoder().decode(ArchiveManifest.self, from: manifestData)
  }

  func validateCompatibility(_ manifest: ArchiveManifest) throws {
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"

    guard manifest.compatibility.isCompatible(with: currentVersion) else {
      throw ImportError.incompatibleVersion
    }
  }

  func readPreset(from archiveURL: URL) async throws -> Preset {
    let presetURL = archiveURL.appendingPathComponent(PresetArchive.presetFileName)
    let presetData = try Data(contentsOf: presetURL)
    return try JSONDecoder().decode(Preset.self, from: presetData)
  }

  func countCustomSounds(in archiveURL: URL) async -> Int {
    let soundsDir = archiveURL.appendingPathComponent(PresetArchive.soundsDirectoryName)
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)

    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      return 0
    }

    do {
      let metadataData = try Data(contentsOf: metadataURL)

      let soundsManifest = try JSONDecoder().decode(SoundsManifest.self, from: metadataData)
      return soundsManifest.customSounds.count
    } catch {
      return 0
    }
  }
}
