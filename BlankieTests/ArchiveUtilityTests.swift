//
//  ArchiveUtilityTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  ArchiveUtility round trips and its defenses against untrusted `.blankie` input
//  (zip-slip, symlinks, entry-count limit).
//

import Foundation
import Testing
import ZIPFoundation

@testable import Blankie

@Suite struct ArchiveUtilityTests {

  @Test func roundTripPreservesFiles() throws {
    let root = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("src", isDirectory: true)
    let nested = source.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("manifest".utf8).write(to: source.appendingPathComponent("manifest.json"))
    try Data("deep".utf8).write(to: nested.appendingPathComponent("deep.txt"))

    let zip = root.appendingPathComponent("out.blankie")
    try ArchiveUtility.create(from: source, to: zip)

    let dest = root.appendingPathComponent("dest", isDirectory: true)
    try ArchiveUtility.extract(from: zip, to: dest)

    let manifest = try Data(contentsOf: dest.appendingPathComponent("manifest.json"))
    let deep = try Data(contentsOf: dest.appendingPathComponent("sub/deep.txt"))
    #expect(String(decoding: manifest, as: UTF8.self) == "manifest")
    #expect(String(decoding: deep, as: UTF8.self) == "deep")
  }

  @Test func zipSlipEntryIsSkipped() throws {
    let outer = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: outer) }

    let zip = outer.appendingPathComponent("evil.zip")
    try ArchiveSupport.makeZip(
      at: zip,
      entries: [
        .init(path: "../escape.txt", data: Data("pwned".utf8)),
        .init(path: "safe.txt", data: Data("ok".utf8)),
      ])

    let dest = outer.appendingPathComponent("extract", isDirectory: true)
    try ArchiveUtility.extract(from: zip, to: dest)

    // The escaping entry resolves to `outer/escape.txt`; it must not exist.
    #expect(
      !FileManager.default.fileExists(atPath: outer.appendingPathComponent("escape.txt").path))
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("safe.txt").path))
  }

  /// A symlink could redirect later writes; the rest of the archive still extracts.
  @Test func symlinkEntryIsSkipped() throws {
    let outer = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: outer) }

    let zip = outer.appendingPathComponent("link.zip")
    try ArchiveSupport.makeZip(
      at: zip,
      entries: [
        .init(path: "evil-link", data: Data("/etc/passwd".utf8), type: .symlink),
        .init(path: "real.txt", data: Data("real".utf8)),
      ])

    let dest = outer.appendingPathComponent("extract", isDirectory: true)
    try ArchiveUtility.extract(from: zip, to: dest)

    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("real.txt").path))
  }

  /// More than `maxEntryCount` (512) entries throws `limitExceeded`.
  @Test func entryCountLimitThrows() throws {
    let outer = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: outer) }

    let zip = outer.appendingPathComponent("bomb.zip")
    let entries = (0..<513).map { ArchiveSupport.CraftedEntry(path: "f\($0).txt") }
    try ArchiveSupport.makeZip(at: zip, entries: entries)

    let dest = outer.appendingPathComponent("extract", isDirectory: true)
    #expect(throws: ArchiveUtility.ArchiveError.self) {
      try ArchiveUtility.extract(from: zip, to: dest)
    }
  }
}
