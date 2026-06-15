//
//  AppGroupFileMirror.swift
//  Blankie
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import os

/// Serializes durable file-mirror I/O in the shared app-group container so
/// concurrent writes to the same path can't interleave or land out of order,
/// and keeps that I/O off the main actor. Owns the low-level read/write/remove
/// primitives shared by the preset-artwork and custom-sound mirrors; each
/// manager still computes its own URLs and decides what to mirror.
actor AppGroupFileMirror {
  static let shared = AppGroupFileMirror()

  /// Atomically write raw data, replacing any existing file.
  func write(_ data: Data, to url: URL) {
    do {
      try AppGroupConfiguration.writeProtectionlessFile(data, to: url)
    } catch {
      Logger.app.error(
        "AppGroupFileMirror: write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  /// Encode `value` as stable (sorted-key) JSON and write only when the on-disk
  /// bytes differ — the read/compare happens here so it can't race a write.
  func writeJSONIfChanged<T: Encodable & Sendable>(_ value: T, to url: URL) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return }
    if let existing = try? Data(contentsOf: url), existing == data { return }
    write(data, to: url)
  }

  func read(at url: URL) -> Data? {
    try? Data(contentsOf: url)
  }

  func remove(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
}
