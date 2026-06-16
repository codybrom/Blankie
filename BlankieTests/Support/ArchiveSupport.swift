//
//  ArchiveSupport.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Builds `.blankie`-style archive directories and ZIP files for tests —
//  including deliberately malicious archives (zip-slip, symlink, entry-count
//  bomb) used to exercise `ArchiveUtility`'s untrusted-input defenses.
//

import Foundation
import ZIPFoundation

@testable import Blankie

enum ArchiveSupport {
  /// Write a minimal, structurally valid archive directory (manifest.json +
  /// preset.json) at `dir`, mirroring what `PresetExporter` produces.
  static func writeValidArchiveDir(
    at dir: URL, preset: Preset, blankieVersion: String = "2.0.0"
  ) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let manifest = ArchiveManifest(blankieVersion: blankieVersion)
    try JSONEncoder().encode(manifest)
      .write(to: dir.appendingPathComponent(PresetArchive.manifestFileName))
    try JSONEncoder().encode(preset)
      .write(to: dir.appendingPathComponent(PresetArchive.presetFileName))
  }

  /// A single entry to place in a crafted ZIP, with full control over its path
  /// and type so tests can construct paths the app's own archiver never would.
  struct CraftedEntry {
    let path: String
    let data: Data
    let type: Entry.EntryType

    init(path: String, data: Data = Data("payload".utf8), type: Entry.EntryType = .file) {
      self.path = path
      self.data = data
      self.type = type
    }
  }

  /// Build a ZIP at `url` containing exactly `entries`. Uses the same
  /// ZIPFoundation API surface as `ArchiveUtility.create`.
  static func makeZip(at url: URL, entries: [CraftedEntry]) throws {
    try? FileManager.default.removeItem(at: url)
    let archive = try Archive(url: url, accessMode: .create)
    for entry in entries {
      try archive.addEntry(
        with: entry.path,
        type: entry.type,
        uncompressedSize: Int64(entry.data.count),
        compressionMethod: .none
      ) { position, size in
        let start = Int(position)
        let end = Swift.min(start + size, entry.data.count)
        guard start < end else { return Data() }
        return entry.data.subdata(in: start..<end)
      }
    }
  }
}
