//
//  PresetImportCollisionTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  An imported archive can carry IDs that already exist (a re-imported export or an edited
//  archive), so nothing is stored under a taken ID. Runs on SingletonSandbox's in-memory store.
//

import Foundation
import SwiftData
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class PresetImportCollisionTests {
  private let sandbox: SingletonSandbox
  private let context: ModelContext

  init() async throws {
    sandbox = await SingletonSandbox.make(soundNames: ["test-import-a"])
    context = try sandbox.installInMemoryStore()
  }

  isolated deinit {
    sandbox.restore()
  }

  private func artworkRows(for presetID: UUID) throws -> [PresetArtwork] {
    try context.fetch(
      FetchDescriptor<PresetArtwork>(predicate: #Predicate { $0.presetId == presetID }))
  }

  // MARK: - Preset artwork

  /// Importing your own export re-IDs the preset before storing its artwork, so
  /// the original keeps its artwork row and the copy gets its own.
  @Test func importingAnExportKeepsTheOriginalsArtwork() async throws {
    sandbox.audioManager.sounds = [TestSound(fileName: "test-import-a")]
    // Unselected, so activating the import can't start playback.
    let original = PresetFactory.makePreset(
      name: "Original",
      soundStates: [PresetState(fileName: "test-import-a", isSelected: false, volume: 0.5)],
      soundOrder: ["test-import-a"])
    let originalArtwork = Data([0x01, 0x02, 0x03])
    let originalArtworkID = try await PresetArtworkManager.shared.saveArtwork(
      originalArtwork, for: original.id, type: .artwork)
    sandbox.presetManager.setPresets([original])

    let archive = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: archive) }
    try ArchiveSupport.writeValidArchiveDir(at: archive, preset: original)
    let exportedArtwork = Data([0x09, 0x09, 0x09])
    try exportedArtwork.write(to: archive.appendingPathComponent(PresetArchive.artworkFileName))

    let imported = try await PresetImporter.shared.importArchive(from: archive)
    await sandbox.waitForPresetApply()
    defer { AnimatedArtworkFileStore.removeItemIfExists(relativePath: imported.staticArtworkPath) }

    #expect(imported.id != original.id)
    let originalRows = try artworkRows(for: original.id)
    #expect(originalRows.map(\.id) == [originalArtworkID])
    #expect(originalRows.first?.imageData == originalArtwork)
    let importedRows = try artworkRows(for: imported.id)
    #expect(importedRows.count == 1)
    #expect(importedRows.first?.imageData == exportedArtwork)

    try? await PresetArtworkManager.shared.deleteArtwork(for: original.id)
    try? await PresetArtworkManager.shared.deleteArtwork(for: imported.id)
  }

  // MARK: - Custom sound IDs

  /// A taken ID with a different SHA gets a fresh ID, and the mapping points the preset at it.
  @Test func importedSoundWithATakenIDGetsAFreshOne() async throws {
    let dir = try sandbox.customSoundsDirectory()
    let takenID = UUID()
    sandbox.trackCustomSound(named: takenID.uuidString)

    let existing = CustomSoundData(
      title: "Mine", systemIconName: "waveform", fileName: takenID.uuidString,
      fileExtension: "wav", originalFileName: "mine.wav")
    existing.id = takenID
    existing.sha256Hash = "existing-hash"
    context.insert(existing)
    try context.save()
    let existingURL = dir.appendingPathComponent("\(takenID.uuidString).wav")
    try TestAudio.writeTone(to: existingURL, seconds: 1, frequency: 440)
    let existingBytes = try Data(contentsOf: existingURL)

    // The archive holds a different file under the same ID.
    let archive = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: archive) }
    let soundsDir = archive.appendingPathComponent(PresetArchive.soundsDirectoryName)
    try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
    try TestAudio.writeTone(
      to: soundsDir.appendingPathComponent("\(takenID.uuidString).wav"), seconds: 1,
      frequency: 880)
    let metadata = CustomSoundMetadata(
      id: takenID, fileName: "\(takenID.uuidString).wav", originalFileName: "theirs.wav",
      title: "Theirs", systemIconName: "waveform", lufsValue: nil, sha256Hash: "other-hash",
      credits: nil)
    try JSONEncoder().encode(SoundsManifest(customSounds: [metadata], builtInCustomizations: []))
      .write(to: soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName))

    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: takenID.uuidString, isSelected: false, volume: 0.5)],
      soundOrder: [takenID.uuidString])
    let mapping = try await PresetImporter.shared.importCustomSounds(for: preset, from: archive)
    let newID = try #require(mapping[takenID])
    sandbox.trackCustomSound(named: newID.uuidString)
    await sandbox.settle()

    #expect(newID != takenID)
    #expect(try Data(contentsOf: existingURL) == existingBytes)
    let rows = try context.fetch(FetchDescriptor<CustomSoundData>())
    #expect(rows.filter { $0.id == takenID }.count == 1)
    #expect(rows.first { $0.id == takenID }?.sha256Hash == "existing-hash")
    #expect(rows.contains { $0.id == newID })
  }
}
