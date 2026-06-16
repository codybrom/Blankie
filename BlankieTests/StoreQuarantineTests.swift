//
//  StoreQuarantineTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The corrupt-store quarantine move. After two consecutive on-disk store-open
//  failures this is the ONLY path that preserves a recoverable copy of the
//  user's preset / custom-sound metadata, so the file move (store + -wal/-shm)
//  must be exact and must keep only the most recent salvage.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct StoreQuarantineTests {

  @Test func movesStoreAndSidecarsPreservingBytes() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let fm = FileManager.default

    let store = dir.appendingPathComponent("Blankie.sqlite")
    let wal = dir.appendingPathComponent("Blankie.sqlite-wal")
    let shm = dir.appendingPathComponent("Blankie.sqlite-shm")
    try Data("STORE".utf8).write(to: store)
    try Data("WAL".utf8).write(to: wal)
    try Data("SHM".utf8).write(to: shm)

    AppSetup.quarantineStore(at: store)

    #expect(!fm.fileExists(atPath: store.path))
    #expect(!fm.fileExists(atPath: wal.path))
    #expect(!fm.fileExists(atPath: shm.path))

    let q = dir.appendingPathComponent("CorruptedStore")
    let movedStore = try Data(contentsOf: q.appendingPathComponent("Blankie.sqlite"))
    let movedWal = try Data(contentsOf: q.appendingPathComponent("Blankie.sqlite-wal"))
    let movedShm = try Data(contentsOf: q.appendingPathComponent("Blankie.sqlite-shm"))
    #expect(movedStore == Data("STORE".utf8))
    #expect(movedWal == Data("WAL".utf8))
    #expect(movedShm == Data("SHM".utf8))
  }

  /// Missing sidecars are skipped, not fatal; the store alone is moved.
  @Test func handlesMissingSidecars() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = dir.appendingPathComponent("Blankie.sqlite")
    try Data("ONLY".utf8).write(to: store)

    AppSetup.quarantineStore(at: store)

    #expect(!FileManager.default.fileExists(atPath: store.path))
    let moved = dir.appendingPathComponent("CorruptedStore/Blankie.sqlite")
    #expect(try Data(contentsOf: moved) == Data("ONLY".utf8))
  }

  /// Quarantining twice keeps only the most recent salvage (the prior
  /// CorruptedStore is replaced, not merged).
  @Test func keepsOnlyMostRecentSalvage() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = dir.appendingPathComponent("Blankie.sqlite")

    try Data("FIRST".utf8).write(to: store)
    AppSetup.quarantineStore(at: store)

    try Data("SECOND".utf8).write(to: store)
    AppSetup.quarantineStore(at: store)

    let moved = dir.appendingPathComponent("CorruptedStore/Blankie.sqlite")
    #expect(try Data(contentsOf: moved) == Data("SECOND".utf8))
  }
}
