//
//  AppGroupFileMirrorTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The durable mirror that rehydrates custom-sound / preset-artwork metadata
//  after a store rebuild. writeJSONIfChanged must skip identical writes (no
//  artwork churn) yet always persist a changed snapshot, encoded with stable
//  (sorted-key) bytes so the compare is deterministic.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct AppGroupFileMirrorTests {

  private func modDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  @Test func writesAndReadsBack() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("mirror.json")
    let value = ["alpha": 1, "beta": 2]

    await AppGroupFileMirror.shared.writeJSONIfChanged(value, to: url)

    let data = try #require(try? Data(contentsOf: url))
    let decoded = try JSONDecoder().decode([String: Int].self, from: data)
    #expect(decoded == value)
  }

  @Test func skipsWriteWhenUnchanged() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("mirror.json")
    let value = ["a": 1, "b": 2, "c": 3]

    await AppGroupFileMirror.shared.writeJSONIfChanged(value, to: url)
    let first = try #require(modDate(url))

    try await Task.sleep(for: .milliseconds(30))
    await AppGroupFileMirror.shared.writeJSONIfChanged(value, to: url)
    let second = try #require(modDate(url))

    #expect(first == second, "an identical value must not rewrite the file")
  }

  @Test func rewritesWhenChanged() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("mirror.json")

    await AppGroupFileMirror.shared.writeJSONIfChanged(["v": 1], to: url)
    await AppGroupFileMirror.shared.writeJSONIfChanged(["v": 2], to: url)

    let data = try #require(try? Data(contentsOf: url))
    let decoded = try JSONDecoder().decode([String: Int].self, from: data)
    #expect(decoded == ["v": 2])
  }
}
