//
//  AppGroupFileMirror.swift
//  Blankie
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import os

/// Serializes app-group file-mirror I/O off the main actor so writes to one path
/// can't interleave. Shared by the preset-artwork and custom-sound mirrors.
actor AppGroupFileMirror {
  static let shared = AppGroupFileMirror()

  func write(_ data: Data, to url: URL) {
    do {
      try AppGroupConfiguration.writeProtectionlessFile(data, to: url)
    } catch {
      Logger.app.error(
        "AppGroupFileMirror: write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  /// Writes sorted-key JSON only when the on-disk bytes differ. The compare runs
  /// inside the actor so it can't race a write.
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
