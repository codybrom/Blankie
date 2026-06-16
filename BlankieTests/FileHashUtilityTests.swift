//
//  FileHashUtilityTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Custom-sound dedup keys off SHA-256. The streaming file hash and the
//  in-memory data hash must agree and match known vectors, or dedup silently
//  fails (duplicate imports) or misfires (distinct files treated as one).
//

import Foundation
import Testing

@testable import Blankie

@Suite struct FileHashUtilityTests {

  /// Known SHA-256 vectors lock the algorithm and hex formatting.
  @Test func dataHashMatchesKnownVectors() {
    #expect(
      FileHashUtility.sha256Hash(for: Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(
      FileHashUtility.sha256Hash(for: Data())
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  /// The streaming file hash equals the in-memory data hash for the same bytes.
  @Test func fileHashMatchesDataHash() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let bytes = Data("the quick brown fox jumps over the lazy dog".utf8)
    let url = dir.appendingPathComponent("sample.bin")
    try bytes.write(to: url)

    #expect(try FileHashUtility.sha256Hash(for: url) == FileHashUtility.sha256Hash(for: bytes))
  }

  /// Different content yields a different hash (no collision passthrough).
  @Test func differentContentDiffers() {
    #expect(
      FileHashUtility.sha256Hash(for: Data("alpha".utf8))
        != FileHashUtility.sha256Hash(for: Data("beta".utf8)))
  }

  /// A payload larger than the 1 MB streaming buffer hashes correctly across
  /// multiple reads — guards the chunked-read loop.
  @Test func largePayloadStreamsAcrossBuffers() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // 3 MB of deterministic, non-repeating-per-byte data spanning several buffers.
    var bytes = Data(count: 3 * 1024 * 1024)
    for i in bytes.indices { bytes[i] = UInt8(i & 0xFF) }
    let url = dir.appendingPathComponent("large.bin")
    try bytes.write(to: url)

    #expect(try FileHashUtility.sha256Hash(for: url) == FileHashUtility.sha256Hash(for: bytes))
  }
}
