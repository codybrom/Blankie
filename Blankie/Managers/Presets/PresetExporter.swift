//
//  PresetExporter.swift
//  Blankie
//
//  Created by Cody Bromley on 6/25/25.
//

import Foundation
import SwiftData
import SwiftUI

class PresetExporter {
  static let shared = PresetExporter()

  private init() {}

  enum ExportError: LocalizedError {
    case archiveCreationFailed
    case missingArtwork
    case missingCustomSound(String)
    case fileSystemError(String)

    var errorDescription: String? {
      switch self {
      case .archiveCreationFailed:
        return "Failed to create preset archive"
      case .missingArtwork:
        return "Missing artwork file"
      case .missingCustomSound(let soundName):
        return "Missing custom sound: \(soundName)"
      case .fileSystemError(let message):
        return "File system error: \(message)"
      }
    }
  }

  func createArchive(for preset: Preset) async throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let archiveDir = tempDir.appendingPathComponent("\(preset.name).blankie-temp")
    let archiveZip = tempDir.appendingPathComponent("\(preset.name).blankie")

    // Remove existing files if they exist
    try? FileManager.default.removeItem(at: archiveDir)
    try? FileManager.default.removeItem(at: archiveZip)

    // Create archive directory
    try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)

    // Create archive manifest
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    let manifest = ArchiveManifest(blankieVersion: currentVersion)

    // Get custom sounds for this preset
    let customSounds = try await getCustomSounds(for: preset)

    // Get sound customizations for this preset
    let soundCustomizations = getSoundCustomizations(for: preset)

    // Create archive object
    let archive = PresetArchive(
      manifest: manifest,
      preset: preset,
      customSounds: customSounds
    )

    // Write archive files
    try await writeManifest(archive.manifest, to: archiveDir)
    try await writePreset(archive.preset, to: archiveDir)
    try await writeArtwork(for: preset, to: archiveDir)
    try await writeCustomSounds(
      customSounds, withCustomizations: soundCustomizations, to: archiveDir
    )

    // Create zip file
    try await createZipFile(from: archiveDir, to: archiveZip)

    // Clean up temporary directory
    try? FileManager.default.removeItem(at: archiveDir)

    return archiveZip
  }

  private func getCustomSounds(for preset: Preset) async throws -> [CustomSoundMetadata] {
    let customSoundManager = CustomSoundManager.shared

    // Get custom sounds on main actor and immediately convert to metadata
    let customSoundMetadata = await MainActor.run {
      let allCustomSounds = customSoundManager.getAllCustomSounds()

      // Filter to sounds used in this preset
      let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
      let relevantCustomSounds = allCustomSounds.filter { customSound in
        presetSoundFileNames.contains(customSound.fileName)
      }

      // Convert to metadata
      return relevantCustomSounds.map { customSound in
        CustomSoundMetadata(from: customSound)
      }
    }

    return customSoundMetadata
  }

  private func writeManifest(_ manifest: ArchiveManifest, to archiveDir: URL) async throws {
    let manifestData = try JSONEncoder().encode(manifest)
    let manifestURL = archiveDir.appendingPathComponent(PresetArchive.manifestFileName)
    try manifestData.write(to: manifestURL)
  }

  private func writePreset(_ preset: Preset, to archiveDir: URL) async throws {
    let presetData = try JSONEncoder().encode(preset)
    let presetURL = archiveDir.appendingPathComponent(PresetArchive.presetFileName)
    try presetData.write(to: presetURL)
  }

  private func writeArtwork(for preset: Preset, to archiveDir: URL) async throws {
    let didWriteStaticArtwork = try await writeStaticArtwork(for: preset, to: archiveDir)
    try await writeCustomAnimatedArtwork(
      for: preset, to: archiveDir, didWriteStaticArtwork: didWriteStaticArtwork)
  }

  private func writeStaticArtwork(for preset: Preset, to archiveDir: URL) async throws -> Bool {
    if let artworkId = preset.artworkId,
      let imageData = await PresetArtworkManager.shared.loadArtworkData(id: artworkId)
    {
      let artworkURL = archiveDir.appendingPathComponent(PresetArchive.artworkFileName)
      try imageData.write(to: artworkURL)
      return true
    } else if let staticPath = preset.staticArtworkPath,
      AnimatedArtworkFileStore.fileExists(at: staticPath)
    {
      let sourceURL = AnimatedArtworkFileStore.absoluteURL(for: staticPath)
      let destination = archiveDir.appendingPathComponent(PresetArchive.artworkFileName)
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.copyItem(at: sourceURL, to: destination)
      return true
    }
    return false
  }

  private func writeCustomAnimatedArtwork(
    for preset: Preset, to archiveDir: URL, didWriteStaticArtwork: Bool
  ) async throws {
    // Only export custom animations (bundled animations are referenced by identifier)
    guard let animated = preset.animatedArtwork,
      animated.source == .custom,
      let loopPath = animated.loopPath,
      AnimatedArtworkFileStore.fileExists(at: loopPath)
    else {
      return
    }

    try writeAnimatedLoop(loopPath: loopPath, to: archiveDir)
    try writeAnimatedPreview(
      animated: animated,
      to: archiveDir,
      staticPath: preset.staticArtworkPath,
      didWriteStaticArtwork: didWriteStaticArtwork
    )
  }

  private func writeAnimatedLoop(loopPath: String, to archiveDir: URL) throws {
    let loopURL = AnimatedArtworkFileStore.absoluteURL(for: loopPath)
    let loopExtension = loopURL.pathExtension.isEmpty ? "mov" : loopURL.pathExtension
    let destination = archiveDir.appendingPathComponent(
      "\(PresetArchive.animatedLoopBaseName).\(loopExtension)")
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: loopURL, to: destination)
  }

  private func writeAnimatedPreview(
    animated: AnimatedArtworkRef, to archiveDir: URL, staticPath: String?,
    didWriteStaticArtwork: Bool
  ) throws {
    let destinationPreview = archiveDir.appendingPathComponent(
      PresetArchive.animatedPreviewFileName)

    if let previewPath = animated.previewPath,
      AnimatedArtworkFileStore.fileExists(at: previewPath)
    {
      let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
      try? FileManager.default.removeItem(at: destinationPreview)
      try FileManager.default.copyItem(at: previewURL, to: destinationPreview)
    } else if !didWriteStaticArtwork,
      let staticPath,
      AnimatedArtworkFileStore.fileExists(at: staticPath)
    {
      let previewURL = AnimatedArtworkFileStore.absoluteURL(for: staticPath)
      try? FileManager.default.removeItem(at: destinationPreview)
      try FileManager.default.copyItem(at: previewURL, to: destinationPreview)
    }
  }

  private func writeCustomSounds(
    _ customSounds: [CustomSoundMetadata], withCustomizations customizations: [SoundCustomization],
    to archiveDir: URL
  )
    async throws
  {
    guard !customSounds.isEmpty || !customizations.isEmpty else { return }

    // Create sounds directory
    let soundsDir = archiveDir.appendingPathComponent(PresetArchive.soundsDirectoryName)
    try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)

    // Write unified sounds metadata including customizations
    let soundsManifest = SoundsManifest(
      customSounds: customSounds, builtInCustomizations: customizations
    )
    let metadataURL = soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName)
    let metadataData = try JSONEncoder().encode(soundsManifest)
    try metadataData.write(to: metadataURL)

    // Copy sound files
    let customSoundManager = CustomSoundManager.shared
    for soundMetadata in customSounds {
      // Get the sound URL on main actor to avoid sending CustomSoundData across actors
      let soundURL = await MainActor.run {
        if let customSoundData = customSoundManager.getCustomSound(by: soundMetadata.id) {
          return customSoundManager.getURLForCustomSound(customSoundData)
        }
        return nil
      }

      if let soundURL = soundURL {
        let destinationURL = soundsDir.appendingPathComponent(soundMetadata.fileName)
        try FileManager.default.copyItem(at: soundURL, to: destinationURL)
      } else {
        throw ExportError.missingCustomSound(soundMetadata.title)
      }
    }
  }

  private func getSoundCustomizations(for preset: Preset) -> [SoundCustomization] {
    let customizationManager = SoundCustomizationManager.shared

    // Get sound file names from the preset
    let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))

    // Get all customizations and filter to those used in this preset
    let allCustomizations = customizationManager.getAllCustomizations()
    return allCustomizations
      .filter { presetSoundFileNames.contains($0.fileName) }
      .compactMap { customization in
        // A built-in sound's name and icon are personal, cosmetic overrides
        // (and a shared preset shouldn't leak them, nor force the recipient's
        // built-in name away from their own localized default). Strip both;
        // behavioral settings still travel. Drop entries left with nothing.
        var stripped = customization
        stripped.customTitle = nil
        stripped.customIconName = nil
        return stripped.hasCustomizations ? stripped : nil
      }
  }

  private func createZipFile(from sourceURL: URL, to destinationURL: URL) async throws {
    try ArchiveUtility.create(from: sourceURL, to: destinationURL)
  }
}
