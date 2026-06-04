//
//  Logging.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//

import Foundation
import os

/// Unified-logging categories, one per functional area. Filter by category in
/// Xcode's console or Console.app (subsystem com.codybrom.blankie).
///
/// Conventions: `.debug` for dev chatter (memory-only, never persisted, near
/// zero cost in release). `.error` for failures — persisted to disk in release
/// builds, so mark interpolated values `privacy: .public` there or they render
/// as <private> in sysdiagnoses.
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
