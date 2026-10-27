//
//  CustomSoundLifecycleTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Custom-sound adds, deletes, conversions and launch recovery, checked against what the
//  mixer and presets hold. Uses an in-memory store (SingletonSandbox); test files go in the
//  real custom-sounds directory and are removed on restore.
//

import AVFoundation
import Foundation
import SwiftData
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class CustomSoundLifecycleTests {
  private let sandbox: SingletonSandbox
  private let context: ModelContext
  private var audioManager: AudioManager { sandbox.audioManager }

  init() async throws {
    sandbox = await SingletonSandbox.make(soundNames: ["test-life-a"])
    context = try sandbox.installInMemoryStore()
  }

  isolated deinit {
    sandbox.restore()
  }

  // MARK: - Helpers

  /// Inserts a row named by its ID, the way imports name custom sounds.
  private func insertRow(title: String, fileExtension: String = "m4a") throws -> CustomSoundData {
    let id = UUID()
    let row = CustomSoundData(
      title: title, systemIconName: "waveform", fileName: id.uuidString,
      fileExtension: fileExtension)
    row.id = id
    context.insert(row)
    try context.save()
    sandbox.trackCustomSound(named: row.fileName)
    return row
  }

  private func standIn(for row: CustomSoundData) -> TestSound {
    TestSound(fileName: row.fileName, isCustom: true, customSoundDataID: row.id)
  }

  private func conversionTempFiles(for fileName: String, in dir: URL) -> [String] {
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return entries.filter { $0.hasPrefix("\(fileName)-aac-") }
  }

  // MARK: - Adds and deletes keep live instances

  /// Solo holds a `Sound` instance, so an add must not rebuild the others.
  @Test func addingASoundKeepsTheSoloedInstance() async throws {
    try #require(audioManager.modelContext != nil, "launch installed the custom-sound observers")
    let soloed = standIn(for: try insertRow(title: "Test A"))
    audioManager.sounds = [soloed]
    audioManager.enterSoloMode(for: soloed, startPlaying: false)

    _ = try insertRow(title: "Test B")
    NotificationCenter.default.post(name: .customSoundAdded, object: nil)
    await sandbox.settle()

    #expect(
      audioManager.sounds.contains { $0 === soloed },
      "sounds were rebuilt: \(audioManager.sounds.map(\.fileName))")
    #expect(audioManager.soloModeSound === soloed)
  }

  @Test func deletingASoundKeepsTheOthersInstances() async throws {
    try #require(audioManager.modelContext != nil, "launch installed the custom-sound observers")
    let soloed = standIn(for: try insertRow(title: "Test A"))
    let doomedRow = try insertRow(title: "Test B")
    let doomed = standIn(for: doomedRow)
    audioManager.sounds = [soloed, doomed]
    audioManager.enterSoloMode(for: soloed, startPlaying: false)

    context.delete(doomedRow)
    try context.save()
    NotificationCenter.default.post(name: .customSoundDeleted, object: nil)
    await sandbox.settle()

    #expect(audioManager.sounds.contains { $0 === soloed })
    #expect(!audioManager.sounds.contains { $0 === doomed })
    #expect(audioManager.soloModeSound === soloed)
  }

  // MARK: - Pruning counts audio on disk

  /// Pruning is irreversible, so a sound with audio on disk but no row (after a store
  /// rebuild) stays in presets.
  @Test func pruningKeepsSoundsWhoseAudioIsOnDisk() throws {
    _ = try insertRow(title: "Other")  // a non-empty store, so pruning runs
    let dir = try sandbox.customSoundsDirectory()
    let rowless = UUID().uuidString
    sandbox.trackCustomSound(named: rowless)
    try Data("audio".utf8).write(to: dir.appendingPathComponent("\(rowless).m4a"))
    let gone = UUID().uuidString

    audioManager.sounds = [TestSound(fileName: "test-life-a")]
    let names = ["test-life-a", rowless, gone]
    sandbox.presetManager.setPresets([
      PresetFactory.makePreset(
        soundStates: names.map { PresetFactory.makeState(fileName: $0) }, soundOrder: names)
    ])

    sandbox.presetManager.cleanupDeletedCustomSounds()

    let kept = sandbox.presetManager.presets.first?.soundStates.map(\.fileName) ?? []
    #expect(kept == ["test-life-a", rowless])
  }

  @Test func onDiskNamesSkipSidecarsAndHiddenFiles() throws {
    let dir = try sandbox.customSoundsDirectory()
    let audio = UUID().uuidString
    let sidecarOnly = UUID().uuidString
    let hidden = ".\(UUID().uuidString)"
    for name in [audio, sidecarOnly, hidden] { sandbox.trackCustomSound(named: name) }
    try Data("audio".utf8).write(to: dir.appendingPathComponent("\(audio).m4a"))
    try Data("{}".utf8).write(
      to: dir.appendingPathComponent("\(sidecarOnly)\(CustomSoundManager.mirrorSuffix)"))
    try Data("x".utf8).write(to: dir.appendingPathComponent(hidden))

    let names = CustomSoundManager.shared.customAudioFileNamesOnDisk()

    #expect(names.contains(audio))
    #expect(!names.contains { $0.hasPrefix(sidecarOnly) })
    #expect(!names.contains(hidden))
  }

  // MARK: - Recovery re-checks the store after its scan

  /// Imports and deletes that land during the off-main scan stand; untouched sidecars
  /// still restore.
  @Test func recoverySkipsWhatChangedDuringTheScan() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let names = ["test-recover-imported", "test-recover-deleted", "test-recover-untouched"]
    for name in names {
      let snapshot = CustomSoundSnapshot(
        CustomSoundData(
          title: name, systemIconName: "waveform", fileName: name, fileExtension: "m4a"))
      try JSONEncoder().encode(snapshot)
        .write(to: dir.appendingPathComponent("\(name)\(CustomSoundManager.mirrorSuffix)"))
      try Data("audio".utf8).write(to: dir.appendingPathComponent("\(name).m4a"))
    }
    let scanned = CustomSoundManager.restorableSnapshots(in: dir, excluding: [])
    #expect(scanned.count == 3)

    // While the scan ran, one sound was imported and another deleted.
    let imported = try #require(scanned.first { $0.fileName == names[0] })
    context.insert(CustomSoundData(imported))
    try context.save()
    try FileManager.default.removeItem(at: dir.appendingPathComponent("\(names[1]).m4a"))

    CustomSoundManager.shared.restoreScannedSnapshots(scanned, in: dir)

    let rows = try context.fetch(FetchDescriptor<CustomSoundData>()).map(\.fileName)
    #expect(rows.filter { $0 == names[0] }.count == 1)
    #expect(!rows.contains(names[1]))
    #expect(rows.contains(names[2]))
  }

  // MARK: - Conversion temp files

  /// The conversion stops before saving a deleted model and moves no .m4a into place.
  @Test func deleteDuringConversionLeavesNothingBehind() async throws {
    let row = try insertRow(title: "Converting", fileExtension: "wav")
    let id = row.id
    let fileName = row.fileName
    let dir = try sandbox.customSoundsDirectory()
    try TestAudio.writeTone(to: dir.appendingPathComponent("\(fileName).wav"))
    audioManager.sounds = [standIn(for: row)]

    let conversion = Task { @MainActor in
      await CustomSoundManager.shared.convertToAAC(soundDataID: id)
    }
    await Task.yield()  // the conversion runs up to its off-main transcode
    context.delete(row)
    try context.save()
    let result = await conversion.value

    guard case .failure(.soundNotFound) = result else {
      Issue.record("Expected .soundNotFound, got \(result)")
      return
    }
    #expect(
      !FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(fileName).m4a").path))
    #expect(conversionTempFiles(for: fileName, in: dir).isEmpty)
    await sandbox.settle()
  }

  /// Each conversion uses its own temp file, so neither can unlink or swap in the
  /// other's half-written output.
  @Test func concurrentConversionsLeaveOneCompleteFile() async throws {
    let row = try insertRow(title: "Converting twice", fileExtension: "wav")
    let id = row.id
    let fileName = row.fileName
    let dir = try sandbox.customSoundsDirectory()
    try TestAudio.writeTone(to: dir.appendingPathComponent("\(fileName).wav"), seconds: 2)
    audioManager.sounds = [standIn(for: row)]

    let convert = { @MainActor in await CustomSoundManager.shared.convertToAAC(soundDataID: id) }
    let first = Task { await convert() }
    let second = Task { await convert() }
    let results = [await first.value, await second.value]

    #expect(results.contains { if case .success = $0 { true } else { false } })
    let converted = try AVAudioFile(forReading: dir.appendingPathComponent("\(fileName).m4a"))
    let seconds = Double(converted.length) / converted.processingFormat.sampleRate
    #expect(abs(seconds - 2) < 0.1, "the final file is complete, not a truncated swap")
    #expect(conversionTempFiles(for: fileName, in: dir).isEmpty)
    #expect(row.fileExtension == "m4a")
    await sandbox.settle()
  }
}
