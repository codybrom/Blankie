//
//  TimeInterval+Clock.swift
//  Blankie
//
//  Created by Cody Bromley on 6/2/26.
//

import Foundation

extension TimeInterval {
  /// Compact `m:ss` clock string, e.g. `"3:05"`, or `"-2:30"` for the sleep-timer
  /// countdown. Uses an ASCII colon to match placeholders like `"--:--"`.
  var minuteSecondClock: String {
    // Int(_:) traps on non-finite or huge values (a malformed file's duration).
    guard isFinite, abs(self) < 1e15 else { return "--:--" }
    let totalSeconds = Int(self)
    let sign = totalSeconds < 0 ? "-" : ""
    let magnitude = abs(totalSeconds)
    return "\(sign)\(String(format: "%d:%02d", magnitude / 60, magnitude % 60))"
  }
}
