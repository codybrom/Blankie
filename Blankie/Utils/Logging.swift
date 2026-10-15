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
///
/// `nonisolated` so categories can be used from off-main code (audio analysis,
/// file mirrors) under module-wide default main-actor isolation. `Logger` is
/// `Sendable`, so sharing these constants across actors is safe.
extension Logger {
  nonisolated private static let subsystem =
    Bundle.main.bundleIdentifier ?? "com.codybrom.blankie"

  nonisolated static let app = Logger(subsystem: subsystem, category: "App")
  nonisolated static let audio = Logger(subsystem: subsystem, category: "Audio")
  nonisolated static let sounds = Logger(subsystem: subsystem, category: "Sounds")
  nonisolated static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
  nonisolated static let presets = Logger(subsystem: subsystem, category: "Presets")
  nonisolated static let settings = Logger(subsystem: subsystem, category: "Settings")
  nonisolated static let carPlay = Logger(subsystem: subsystem, category: "CarPlay")
  nonisolated static let ui = Logger(subsystem: subsystem, category: "UI")
}
