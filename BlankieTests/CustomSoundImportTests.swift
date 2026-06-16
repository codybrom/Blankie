//
//  CustomSoundImportTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The picker import path must stamp a SHA-256 hash on the record so re-imports
//  dedup and the durable mirror persists a real integrity hash. Regression
//  guard: createCustomSoundRecord previously never set sha256Hash (only the
//  preset-import path did), so picker imports persisted a nil hash.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor
struct CustomSoundImportTests {

  @Test func createCustomSoundRecordSetsSha256Hash() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // Any bytes are enough — the file only needs to exist to be hashed; audio
    // analysis returns gracefully (nil LUFS) on a non-audio file.
    let copied = dir.appendingPathComponent("imported.m4a")
    try Data("synthetic bytes for hashing".utf8).write(to: copied)
    let source = dir.appendingPathComponent("original.m4a")
    try Data("source".utf8).write(to: source)

    let importData = SoundImportData(
      sourceURL: source, copiedURL: copied, title: "My Import",
      iconName: "waveform", uniqueFileName: "test-imported", fileExtension: "m4a",
      randomizeStartPosition: true)

    let record = try await CustomSoundManager.shared.createCustomSoundRecord(from: importData)
    defer { PlaybackProfileStore.shared.removeProfile(for: "test-imported") }

    let expected = try FileHashUtility.sha256Hash(for: copied)
    #expect(record.sha256Hash == expected)
    #expect(record.sha256Hash != nil)
  }
}
