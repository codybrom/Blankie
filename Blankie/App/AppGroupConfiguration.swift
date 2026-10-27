//
//  AppGroupConfiguration.swift
//  Blankie
//
//  Created by Cody Bromley on 7/12/25.
//

import Foundation
import os

nonisolated struct AppGroupConfiguration {
  /// `APP_GROUP_IDENTIFIER` from Info.plist, else `group.<bundle id>`.
  static var identifier: String? {
    if let appGroupID = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String
    {
      return appGroupID
    }

    if let bundleID = Bundle.main.bundleIdentifier {
      return "group.\(bundleID)"
    }

    return nil
  }

  static var sharedDefaults: UserDefaults? {
    guard let identifier = identifier else { return nil }
    return UserDefaults(suiteName: identifier)
  }

  static var containerURL: URL? {
    guard let identifier = identifier else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  static var dataStoreURL: URL? {
    containerURL?.appendingPathComponent("Blankie.sqlite")
  }

  nonisolated static var documentsURL: URL? {
    containerURL?.appendingPathComponent("Documents", isDirectory: true)
  }

  static func setupDirectories() {
    guard let documentsURL = documentsURL else { return }

    do {
      try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
      Logger.app.debug("AppGroup: Created shared documents directory")
    } catch {
      Logger.app.error("AppGroup: Failed to create documents directory: \(error, privacy: .public)")
    }
  }

  /// Atomically writes `data` with no file protection so it's readable before first
  /// unlock (headless CarPlay launch), like the SQLite store and audio files.
  nonisolated static func writeProtectionlessFile(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.none])
    try data.write(to: url, options: .atomic)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
  }
}
