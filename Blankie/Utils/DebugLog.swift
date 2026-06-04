//
//  DebugLog.swift
//  Blankie
//
//  Created by Cody Bromley.
//

import Foundation
import os

/// Unified-logging categories, one per functional area. Filter by category in
/// Xcode's console or Console.app (subsystem com.codybrom.blankie).
extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.codybrom.blankie"

  static let app = Logger(subsystem: subsystem, category: "App")
  static let audio = Logger(subsystem: subsystem, category: "Audio")
  static let sounds = Logger(subsystem: subsystem, category: "Sounds")
  static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
  static let presets = Logger(subsystem: subsystem, category: "Presets")
  static let settings = Logger(subsystem: subsystem, category: "Settings")
  static let carPlay = Logger(subsystem: subsystem, category: "CarPlay")
  static let ui = Logger(subsystem: subsystem, category: "UI")
}

#if DEBUG
  private let debugLogStart = Date()
#endif

/// Debug-level chatter, DEBUG builds only (memory-only, never persisted).
/// The `@autoclosure` means release builds never evaluate the message. Each
/// line is prefixed with seconds since launch for at-a-glance phase timing.
func debugLog(_ message: @autoclosure () -> String, _ logger: Logger = .app) {
  #if DEBUG
    let elapsed = String(format: "%8.3f", Date().timeIntervalSince(debugLogStart))
    let text = message()
    logger.debug("[\(elapsed, privacy: .public)] \(text, privacy: .public)")
  #endif
}

/// Error-level logging in ALL builds. Persisted to disk by the system, so
/// failures show up in Console.app and user sysdiagnoses from release builds.
func logError(_ message: String, _ logger: Logger = .app) {
  logger.error("\(message, privacy: .public)")
}
