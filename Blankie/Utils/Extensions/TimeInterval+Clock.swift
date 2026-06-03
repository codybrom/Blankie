//
//  TimeInterval+Clock.swift
//  Blankie
//

import Foundation

extension TimeInterval {
  /// Formats the interval as a compact `m:ss` clock string, e.g. `"3:05"`.
  ///
  /// Minutes are unpadded and seconds are zero-padded to two digits, using a
  /// fixed ASCII colon so the value stays visually consistent with hand-built
  /// placeholders like `"--:--"`. Shared by the sound-info and Now Playing
  /// duration labels (single source for what used to be three copies).
  ///
  /// Negative intervals format with a single leading minus (e.g. `"-2:30"`),
  /// used for the sleep-timer "time left" countdown.
  var minuteSecondClock: String {
    let totalSeconds = Int(self)
    let sign = totalSeconds < 0 ? "-" : ""
    let magnitude = abs(totalSeconds)
    return "\(sign)\(String(format: "%d:%02d", magnitude / 60, magnitude % 60))"
  }
}
