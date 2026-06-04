//
//  DebugLog.swift
//  Blankie
//
//  Created by Cody Bromley.
//

import Foundation

/// Logs a message to the console in DEBUG builds only.
///
/// Drop-in replacement for `print()` so internal diagnostics never reach the
/// device console — or incur string-interpolation cost — in shipping builds.
/// The message is an `@autoclosure`, so in release builds it is never
/// evaluated, which matters for the high-frequency logging in views like
/// `MixerView` whose `onChange`/`onAppear` closures interpolate state on every
/// update.
#if DEBUG
  private let debugLogStart = Date()
#endif

func debugLog(_ message: @autoclosure () -> String) {
  #if DEBUG
    print(String(format: "[%8.3f] ", Date().timeIntervalSince(debugLogStart)) + message())
  #endif
}
