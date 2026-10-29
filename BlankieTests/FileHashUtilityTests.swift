//
//  FileHashUtilityTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  SHA-256 hashing for custom-sound dedup. The streaming file hash must match the
//  in-memory data hash and known vectors.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct FileHashUtilityTests {

  @Test func dataHashMatchesKnownVectors() {
    #expect(
      FileHashUtility.sha256Hash(for: Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(
      FileHashUtility.sha256Hash(for: Data())
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  @Test func fileHashMatchesDataHash() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let bytes = Data("the quick brown fox jumps over the lazy dog".utf8)
    let url = dir.appendingPathComponent("sample.bin")
    try bytes.write(to: url)

    #expect(try await FileHashUtility.sha256Hash(for: url) == FileHashUtility.sha256Hash(for: bytes))
  }

  @Test func differentContentDiffers() {
    #expect(
      FileHashUtility.sha256Hash(for: Data("alpha".utf8))
        != FileHashUtility.sha256Hash(for: Data("beta".utf8)))
  }

  /// Larger than the 1 MB streaming buffer, so it covers the chunked-read loop.
  @Test func largePayloadStreamsAcrossBuffers() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // 3 MB of deterministic, non-repeating-per-byte data spanning several buffers.
    var bytes = Data(count: 3 * 1024 * 1024)
    for i in bytes.indices { bytes[i] = UInt8(i & 0xFF) }
    let url = dir.appendingPathComponent("large.bin")
    try bytes.write(to: url)

    #expect(try await FileHashUtility.sha256Hash(for: url) == FileHashUtility.sha256Hash(for: bytes))
  }

  /// A cancelled import stops hashing at the next read.
  @Test func cancelledHashThrowsCancellation() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("large.bin")
    try Data(count: 3 * 1024 * 1024).write(to: url)

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await FileHashUtility.sha256Hash(for: url)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
