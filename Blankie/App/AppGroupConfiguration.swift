//
//  AppGroupConfiguration.swift
//  Blankie
//
//  Created by Cody Bromley on 7/12/25.
//

import Foundation
import os

/// Configuration for app group shared between main app and CarPlay
nonisolated struct AppGroupConfiguration {
  /// Get the app group identifier from the bundle's entitlements
  static var identifier: String? {
    // Try to get from Info.plist first (if set as a custom key)
    if let appGroupID = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String
    {
      return appGroupID
    }

    // Otherwise, construct from bundle identifier
    if let bundleID = Bundle.main.bundleIdentifier {
      return "group.\(bundleID)"
    }

    return nil
  }

  /// Shared UserDefaults instance for app group
  static var sharedDefaults: UserDefaults? {
    guard let identifier = identifier else { return nil }
    return UserDefaults(suiteName: identifier)
  }

  /// URL for shared container directory
  static var containerURL: URL? {
    guard let identifier = identifier else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  /// URL for SwiftData store in shared container
  static var dataStoreURL: URL? {
    containerURL?.appendingPathComponent("Blankie.sqlite")
  }

  /// URL for shared documents directory
  nonisolated static var documentsURL: URL? {
    containerURL?.appendingPathComponent("Documents", isDirectory: true)
  }

  /// Create necessary directories in shared container
  static func setupDirectories() {
    guard let documentsURL = documentsURL else { return }

    do {
      try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
      Logger.app.debug("AppGroup: Created shared documents directory")
    } catch {
      Logger.app.error("AppGroup: Failed to create documents directory: \(error, privacy: .public)")
    }
  }

  /// Atomically write `data` to a file in the shared container with no file
  /// protection, creating intermediate directories. No protection so a locked
  /// device or headless CarPlay launch before first unlock can still read it
  /// (parity with the SQLite store and audio files). Used by the durable file
  /// mirrors for preset artwork and custom-sound metadata.
  nonisolated static func writeProtectionlessFile(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.none])
    // Atomic replace so a crash mid-write can't leave a truncated file.
    try data.write(to: url, options: .atomic)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
  }
}
