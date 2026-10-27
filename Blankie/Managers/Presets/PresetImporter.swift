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

      // A preset previously imported from this archive, by original ID.
      if let duplicate = existingPresets.first(where: { $0.originalId == preset.id }) {
        Logger.presets.debug(
          "Import: Found previously imported preset with original ID \(preset.id)")
        return duplicate
      }

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

      if !existingNames.contains(baseName) {
        return baseName
      }

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
      let customSoundManager = CustomSoundManager.shared
      let existingSounds = customSoundManager.getAllCustomSounds()

      if let existingSound = existingSounds.first(where: { $0.id == soundMetadata.id }) {
        return ExistingSoundInfo(id: existingSound.id, sha256Hash: existingSound.sha256Hash)
      }

      // Fall back to the original filename and title in case the ID changed.
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
      // Customizations are optional, so don't throw.
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
        // Keep this device's existing customization for the sound.
        if customizationManager.getCustomization(for: customization.fileName) != nil {
          skippedCount += 1
          continue
        }

        // A built-in sound's name and icon are the exporter's personal overrides,
        // and older archives may carry them. Apply only the behavioral settings.
        if let randomizeStart = customization.randomizeStartPosition {
          customizationManager.setRandomizeStartPosition(
            randomizeStart, for: customization.fileName
          )
        }
        if let normalizeAudio = customization.normalizeAudio {
          customizationManager.setNormalizeAudio(normalizeAudio, for: customization.fileName)
        }
        if let volumeAdjustment = customization.volumeAdjustment, volumeAdjustment.isFinite {
          // Clamp to the editor slider's range, since an archive can carry anything.
          customizationManager.setVolumeAdjustment(
            min(max(volumeAdjustment, 0.5), 8.0), for: customization.fileName)
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
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let (archiveURL, tempExtractedURL) = try await extractArchive(from: url)

    defer {
      if let tempURL = tempExtractedURL {
        try? FileManager.default.removeItem(at: tempURL)
        Logger.presets.debug("Import: Cleaned up extracted files at \(tempURL.lastPathComponent)")
      }
      // Remove the imported file if it's in a tmp directory.
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

    // Re-ID the preset before anything is stored under its ID, so saving artwork
    // can't replace the exporting preset's (or an earlier import's) artwork.
    preset = createNewPresetInstance(from: preset)

    try await importArtwork(for: &preset, from: archiveURL)

    // Apply customizations before importing sounds. Each import posts .customSoundAdded,
    // which creates a default customization that importFromManifest would then skip over.
    try await SoundCustomizationImporter.importFromManifest(from: archiveURL)
    let idMapping = try await importCustomSounds(for: preset, from: archiveURL)

    // Imported custom sounds can get fresh IDs, so remap the preset's sound states.
    if !idMapping.isEmpty {
      preset = updatePresetSoundStates(preset, with: idMapping)
    }

    await addAndActivatePreset(preset)

    return preset
  }

  // @concurrent so the CPU-heavy unzip runs off the main actor.
  @concurrent private func extractArchive(from url: URL) async throws -> (
    archiveURL: URL, tempExtractedURL: URL?
  ) {
    var archiveURL = url
    var tempExtractedURL: URL?

    // A compressed .blankie is a file; an already-extracted archive is a directory.
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    {
      Logger.presets.debug("Import: Detected compressed .blankie file, extracting...")

      let tempDir = FileManager.default.temporaryDirectory
      let extractionDir = tempDir.appendingPathComponent("blankie-import-\(UUID().uuidString)")

      do {
        try FileManager.default.createDirectory(
          at: extractionDir, withIntermediateDirectories: true
        )

        try ArchiveUtility.extract(from: url, to: extractionDir)

        archiveURL = extractionDir
        tempExtractedURL = extractionDir
        Logger.presets.debug("Import: Successfully extracted to \(extractionDir.lastPathComponent)")

      } catch {
        // importArchive's cleanup never sees this directory, so remove partial
        // output (say, from an aborted zip bomb) here.
        try? FileManager.default.removeItem(at: extractionDir)
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

    // The archive's sound metadata carries both the custom sounds and their customizations.
    guard let soundsManifest = try readSoundsManifest(from: soundsDir),
      !soundsManifest.customSounds.isEmpty
    else {
      return [:]
    }
    let customSounds = soundsManifest.customSounds
    let customizations = soundsManifest.builtInCustomizations

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

  /// The archive's `metadata.json`, decoded once; `nil` when the file is absent.
  private func readSoundsManifest(from soundsDir: URL) throws -> SoundsManifest? {
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      return nil
    }

    let metadataData = try Data(contentsOf: metadataURL)
    return try JSONDecoder().decode(SoundsManifest.self, from: metadataData)
  }

  @MainActor
  private func processExistingSound(
    _ soundMetadata: CustomSoundMetadata,
    _ existingSound: ExistingSoundInfo,
    _ importedCount: inout Int
  ) async -> UUID? {
    Logger.presets.debug(
      "Import: Sound '\(soundMetadata.title)' already exists with ID \(existingSound.id)")

    if let existingHash = existingSound.sha256Hash,
      let importHash = soundMetadata.sha256Hash,
      existingHash != importHash
    {
      Logger.presets.debug(
        "Import: SHA hash mismatch for '\(soundMetadata.title)' - treating as different file")
      return nil  // Continue with import as it's a different file
    }

    // Same file: skip the import but record the ID mapping.
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

    // Prefer the UUID in the filename when it differs from the metadata ID.
    let fileNameWithoutExt = (soundFileURL.lastPathComponent as NSString).deletingPathExtension
    var actualId: UUID
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

    // The ID names the stored file, so an ID already in use (say, a SHA mismatch)
    // gets a fresh one; idMapping remaps the preset.
    if CustomSoundManager.shared.getCustomSound(by: actualId) != nil
      || CustomSoundManager.shared.customAudioFileNamesOnDisk().contains(actualId.uuidString)
    {
      actualId = UUID()
    }

    do {
      let fileNameWithoutExtension = (soundMetadata.fileName as NSString).deletingPathExtension
      let iconFromCustomization = customizations.first(where: {
        $0.fileName == fileNameWithoutExtension
      })?.customIconName

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

      // Reuses the archive's LUFS value without re-analyzing.
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

      importedCount += 1

      return actualId

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
    let fileNameWithoutExtension = (soundMetadata.fileName as NSString).deletingPathExtension
    let fileExtension = (soundMetadata.fileName as NSString).pathExtension

    let iconName =
      customizations.first(where: { $0.fileName == fileNameWithoutExtension })?.customIconName
      ?? soundMetadata.systemIconName
      ?? "waveform.circle"  // Default icon for older imports

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

    // Record the static artwork path only once the file is written. `artworkId`
    // is stored separately, so the artwork survives a failed write.
    let staticId = UUID()
    let staticRel = AnimatedArtworkFileStore.makeRelativePreviewPath(for: staticId)
    do {
      _ = try AnimatedArtworkFileStore.writeData(artworkData, to: staticRel)
      preset.staticArtworkPath = staticRel
    } catch {
      Logger.presets.error(
        "Import: Failed to write static artwork: \(error, privacy: .public)")
    }
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

    var updatedAnimated = animated
    updatedAnimated.loopPath = nil
    updatedAnimated.bundledIdentifier = bundledId

    // Preview images are bundled, not in the asset pack. Copy them synchronously so
    // the paths are on the preset before importArchive stores it.
    if let previewURL = Bundle.main.url(
      forResource: bundledId, withExtension: "jpg"),
      let squarePreviewURL = Bundle.main.url(
        forResource: "\(bundledId)Square", withExtension: "jpg")
    {
      let assetId = UUID()
      let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
        for: assetId, fileExtension: "jpg")
      let squarePreviewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
        for: assetId, fileExtension: "jpg", suffix: "Square")
      do {
        _ = try AnimatedArtworkFileStore.copyItem(at: previewURL, to: previewRel)
        updatedAnimated.previewPath = previewRel
      } catch {
        Logger.presets.error(
          "Import: Failed to copy preview for '\(bundledId, privacy: .public)': \(error, privacy: .public)"
        )
      }
      do {
        _ = try AnimatedArtworkFileStore.copyItem(at: squarePreviewURL, to: squarePreviewRel)
        updatedAnimated.squarePreviewPath = squarePreviewRel
      } catch {
        Logger.presets.error(
          "Import: Failed to copy square preview for '\(bundledId, privacy: .public)': \(error, privacy: .public)"
        )
      }
    } else {
      Logger.presets.error(
        "Import: Failed to find preview images for '\(bundledId, privacy: .public)'")
    }

    preset.animatedArtwork = updatedAnimated

    // Best effort: download the asset pack variant this device plays (square on iPad).
    Task { @MainActor in
      let packID = BackgroundResourceManager.preferredPackID(for: bundledId)
      do {
        _ = try await BackgroundResourceManager.shared.resourceURL(for: packID)
        Logger.presets.debug("Import: Downloaded artwork pack '\(packID)'")
      } catch {
        Logger.presets.error(
          "Import: Failed to download artwork pack '\(bundledId, privacy: .public)': \(error, privacy: .public)"
        )
        // The preset still works without animated artwork.
      }
    }
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
      do {
        _ = try AnimatedArtworkFileStore.copyItem(at: previewSource, to: previewRel)
        return previewRel
      } catch {
        Logger.presets.error(
          "Import: Failed to copy animated preview: \(error, privacy: .public)")
        // Fall through to the static preview so we never return an unwritten path.
      }
    }
    if let staticPath, AnimatedArtworkFileStore.fileExists(at: staticPath) {
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

    updatedPreset.soundStates = preset.soundStates.map { state in
      // A custom sound's fileName is its UUID string.
      if let soundId = UUID(uuidString: state.fileName),
        let mappedId = idMapping[soundId]
      {
        let updatedState = PresetState(
          fileName: mappedId.uuidString,
          isSelected: state.isSelected,
          volume: state.volume
        )
        Logger.presets.debug(
          "Import: Updated sound state from \(state.fileName) to \(mappedId.uuidString)")
        return updatedState
      }

      return state
    }

    return updatedPreset
  }

  func createNewPresetInstance(from preset: Preset) -> Preset {
    let newPreset = Preset(
      id: UUID(),
      name: preset.name,
      soundStates: preset.soundStates,
      isDefault: false,
      createdVersion: preset.createdVersion,
      lastModifiedVersion: Bundle.main.appVersion,
      soundOrder: preset.soundOrder,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId,
      animatedArtwork: preset.animatedArtwork,
      staticArtworkPath: preset.staticArtworkPath,
      order: preset.order,
      isImported: true,
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

      let customSoundIds = preset.soundStates
        .compactMap { state -> UUID? in
          return UUID(uuidString: state.fileName)
        }

      // Skip ids already loaded. Reloading them would orphan the instances
      // single sound, preview, or Quick Mix still hold.
      let loadedIds = Set(audioManager.sounds.compactMap(\.customSoundDataID))
      let newIds = Set(customSoundIds).subtracting(loadedIds)
      if !newIds.isEmpty {
        audioManager.loadCustomSoundsByIds(newIds)
      }

      var currentPresets = presetManager.presets
      currentPresets.append(preset)
      presetManager.setPresets(currentPresets)

      if preset.artworkId != nil {
        Task {
          await presetManager.cacheThumbnail(for: preset)
        }
      }

      presetManager.savePresets()

      // Activate the imported preset immediately. Leave single sound/Quick Mix first, or
      // single sound skips the apply and a Quick Mix exit would discard it.
      do {
        audioManager.leaveTransientModes()
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
    let currentVersion = Bundle.main.appVersion

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
