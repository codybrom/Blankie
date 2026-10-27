//
//  Logging.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//

import Foundation
import os

/// Unified-logging categories, one per functional area (subsystem
/// com.codybrom.blankie).
///
/// `.debug` is memory-only dev chatter. `.error` persists in release builds, so
/// mark interpolated values `privacy: .public` or they show as <private>.
///
/// `nonisolated` so off-main code (audio analysis, file mirrors) can log under
/// default main-actor isolation. `Logger` is `Sendable`.
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
