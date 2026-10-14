//
//  StoreMigrationCopyTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Moving the SwiftData store into the app group copies its main, -wal, and
//  -shm files as a set. The next launch treats an existing main file as a
//  finished migration, so a copy that fails partway must leave no main file
//  behind, and that launch must not open a store at the destination either.
//  Uses temp directories only, never the real store.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor struct StoreMigrationCopyTests {

  private func writeStore(at storeURL: URL, extensions: [String]) throws {
    for ext in extensions {
      try Data("store\(ext)".utf8).write(to: URL(fileURLWithPath: storeURL.path + ext))
    }
  }

  private func entries(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
  }

  /// A full copy moves every file into place and leaves no staged files.
  @Test func copiesTheWholeSet() throws {
    let source = TestSupport.makeTempDir()
    let destination = TestSupport.makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    let storeURL = source.appendingPathComponent("default.store")
    let groupURL = destination.appendingPathComponent("Blankie.store")
    try writeStore(at: storeURL, extensions: ["", "-wal", "-shm"])

    try AppDataMigrator.copyStoreAtomically(from: storeURL, to: groupURL)

    #expect(
      entries(in: destination) == ["Blankie.store", "Blankie.store-shm", "Blankie.store-wal"])
    #expect(try Data(contentsOf: groupURL) == Data("store".utf8))
  }

  /// A -wal that can't be read fails the copy after the main file was staged.
  /// No main file may appear, since the next launch would accept it as a
  /// complete store.
  @Test func failedCopyLeavesNoMainFile() throws {
    let source = TestSupport.makeTempDir()
    let destination = TestSupport.makeTempDir()
    let storeURL = source.appendingPathComponent("default.store")
    let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: walURL.path)
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    let groupURL = destination.appendingPathComponent("Blankie.store")
    try writeStore(at: storeURL, extensions: ["", "-wal"])
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: walURL.path)

    #expect(throws: (any Error).self) {
      try AppDataMigrator.copyStoreAtomically(from: storeURL, to: groupURL)
    }
    #expect(!FileManager.default.fileExists(atPath: groupURL.path))
    #expect(entries(in: destination).isEmpty, "staged files are cleaned up too")
  }

  /// A rerun after a failed copy replaces stale -wal/-shm files from that run.
  @Test func rerunReplacesStaleSidecars() throws {
    let source = TestSupport.makeTempDir()
    let destination = TestSupport.makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    let storeURL = source.appendingPathComponent("default.store")
    let groupURL = destination.appendingPathComponent("Blankie.store")
    try writeStore(at: storeURL, extensions: ["", "-wal"])
    try Data("stale".utf8).write(to: URL(fileURLWithPath: groupURL.path + "-wal"))

    try AppDataMigrator.copyStoreAtomically(from: storeURL, to: groupURL)

    #expect(
      try Data(contentsOf: URL(fileURLWithPath: groupURL.path + "-wal")) == Data("store-wal".utf8))
  }

  /// After a failed copy the launch runs on an in-memory store. A new store at
  /// the app-group location would read as a finished migration next launch and
  /// strand the legacy rows for good.
  @Test func pendingCopyKeepsTheStoreInMemory() {
    let originalState = AppSetup.storeState
    defer {
      AppSetup.storeCopyPending = false
      AppSetup.storeState = originalState
    }
    AppSetup.storeCopyPending = true

    let container = AppSetup.createModelContainer()

    #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    #expect(AppSetup.storeState == .temporaryInMemory)
  }
}
