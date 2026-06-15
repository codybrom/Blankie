//
//  CustomSoundMirrorTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import Testing

@testable import Blankie

/// Covers the custom-sound file mirror: the snapshot must losslessly capture
/// every persisted field, and the launch reconcile must restore exactly the
/// rows that are safe to restore.
@Suite(.serialized) @MainActor
struct CustomSoundMirrorTests {

  /// A model with every field set to a non-default value, so a round-trip that
  /// drops any field is detectable.
  private func makePopulatedModel() -> CustomSoundData {
    let model = CustomSoundData(
      title: "Rainstorm",
      systemIconName: "cloud.rain",
      fileName: "ABC-123",
      fileExtension: "m4a",
      originalFileName: "rain.wav",
      randomizeStartPosition: false,
      loopSound: false,
      normalizeAudio: false,
      volumeAdjustment: 2.5,
      detectedPeakLevel: -3.2,
      detectedLUFS: -18.0,
      normalizationFactor: 1.4,
      creditAuthor: "Jane Doe",
      creditSourceUrl: "https://example.com/source",
      creditLicenseType: "CC-BY",
      creditCustomLicenseText: "Custom terms",
      creditCustomLicenseUrl: "https://example.com/license",
      importedFromPresetId: UUID(),
      importedFromPresetName: "Sleep",
      moods: Array(SoundMood.allCases.prefix(2)),
      duration: 123.4)
    model.id = UUID()
    model.dateAdded = Date(timeIntervalSince1970: 1_700_000_000)
    model.sha256Hash = "deadbeef"
    model.id3Title = "ID3 Title"
    model.id3Artist = "ID3 Artist"
    model.id3Album = "ID3 Album"
    model.id3Comment = "ID3 Comment"
    model.id3Url = "https://example.com/id3"
    return model
  }

  /// The snapshot must capture, encode, and rebuild every persisted field. If a
  /// field is added to `CustomSoundData` but not mirrored, this fails — the guard
  /// against silent metadata loss when a row is restored after a store rebuild.
  @Test func snapshotRoundTripPreservesEveryField() throws {
    let model = makePopulatedModel()

    let data = try JSONEncoder().encode(CustomSoundSnapshot(model))
    let rebuilt = CustomSoundData(try JSONDecoder().decode(CustomSoundSnapshot.self, from: data))

    #expect(rebuilt.id == model.id)
    #expect(rebuilt.title == model.title)
    #expect(rebuilt.systemIconName == model.systemIconName)
    #expect(rebuilt.fileName == model.fileName)
    #expect(rebuilt.fileExtension == model.fileExtension)
    #expect(rebuilt.dateAdded == model.dateAdded)
    #expect(rebuilt.randomizeStartPosition == model.randomizeStartPosition)
    #expect(rebuilt.loopSound == model.loopSound)
    #expect(rebuilt.normalizeAudio == model.normalizeAudio)
    #expect(rebuilt.volumeAdjustment == model.volumeAdjustment)
    #expect(rebuilt.detectedPeakLevel == model.detectedPeakLevel)
    #expect(rebuilt.detectedLUFS == model.detectedLUFS)
    #expect(rebuilt.normalizationFactor == model.normalizationFactor)
    #expect(rebuilt.sha256Hash == model.sha256Hash)
    #expect(rebuilt.originalFileName == model.originalFileName)
    #expect(rebuilt.creditAuthor == model.creditAuthor)
    #expect(rebuilt.creditSourceUrl == model.creditSourceUrl)
    #expect(rebuilt.creditLicenseType == model.creditLicenseType)
    #expect(rebuilt.creditCustomLicenseText == model.creditCustomLicenseText)
    #expect(rebuilt.creditCustomLicenseUrl == model.creditCustomLicenseUrl)
    #expect(rebuilt.id3Title == model.id3Title)
    #expect(rebuilt.id3Artist == model.id3Artist)
    #expect(rebuilt.id3Album == model.id3Album)
    #expect(rebuilt.id3Comment == model.id3Comment)
    #expect(rebuilt.id3Url == model.id3Url)
    #expect(rebuilt.importedFromPresetId == model.importedFromPresetId)
    #expect(rebuilt.importedFromPresetName == model.importedFromPresetName)
    #expect(rebuilt.moods == model.moods)
    #expect(rebuilt.duration == model.duration)
  }

  /// A sidecar whose audio file is present and whose row is missing is restored.
  @Test func reconcileRestoresSidecarWhenAudioPresent() throws {
    try withTemporaryDirectory { dir in
      let snapshot = CustomSoundSnapshot(makePopulatedModel())
      try writeSidecar(snapshot, in: dir)
      try writeAudio(for: snapshot, in: dir)

      let restored = CustomSoundManager.restorableSnapshots(in: dir, excluding: [])
      #expect(restored.count == 1)
      #expect(restored.first?.fileName == snapshot.fileName)
      #expect(restored.first?.title == snapshot.title)
    }
  }

  /// A sidecar with no audio file is skipped — restoring it would just create a
  /// row that can't load.
  @Test func reconcileSkipsSidecarWithoutAudio() throws {
    try withTemporaryDirectory { dir in
      let snapshot = CustomSoundSnapshot(makePopulatedModel())
      try writeSidecar(snapshot, in: dir)
      // No audio file written.
      #expect(CustomSoundManager.restorableSnapshots(in: dir, excluding: []).isEmpty)
    }
  }

  /// A sidecar whose row already exists in the store is skipped (no duplicates).
  @Test func reconcileSkipsRowsThatAlreadyExist() throws {
    try withTemporaryDirectory { dir in
      let snapshot = CustomSoundSnapshot(makePopulatedModel())
      try writeSidecar(snapshot, in: dir)
      try writeAudio(for: snapshot, in: dir)

      let restored = CustomSoundManager.restorableSnapshots(in: dir, excluding: [snapshot.fileName])
      #expect(restored.isEmpty)
    }
  }

  // MARK: - Helpers

  private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
  }

  private func writeSidecar(_ snapshot: CustomSoundSnapshot, in dir: URL) throws {
    let url = dir.appendingPathComponent("\(snapshot.fileName)\(CustomSoundManager.mirrorSuffix)")
    try JSONEncoder().encode(snapshot).write(to: url)
  }

  private func writeAudio(for snapshot: CustomSoundSnapshot, in dir: URL) throws {
    let url = dir.appendingPathComponent("\(snapshot.fileName).\(snapshot.fileExtension)")
    try Data("audio".utf8).write(to: url)
  }
}
