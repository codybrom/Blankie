//
//  TimeIntervalClockTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The `m:ss` formatter shared by sound-info and Now Playing duration labels
//  and the sleep-timer countdown. Seconds must zero-pad and negatives must show
//  a single leading minus (guards the "-3:5" style bug).
//

import Foundation
import Testing

@testable import Blankie

@Suite struct TimeIntervalClockTests {

  @Test func formatsPositiveIntervals() {
    #expect(TimeInterval(0).minuteSecondClock == "0:00")
    #expect(TimeInterval(5).minuteSecondClock == "0:05")
    #expect(TimeInterval(59).minuteSecondClock == "0:59")
    #expect(TimeInterval(60).minuteSecondClock == "1:00")
    #expect(TimeInterval(185).minuteSecondClock == "3:05")
  }

  /// Minutes are unpadded and may exceed 60 (no hours rollover).
  @Test func minutesAreUnboundedAndUnpadded() {
    #expect(TimeInterval(3661).minuteSecondClock == "61:01")
  }

  /// Negative intervals (sleep-timer countdown) carry exactly one leading minus
  /// and still zero-pad seconds.
  @Test func formatsNegativeIntervals() {
    #expect(TimeInterval(-5).minuteSecondClock == "-0:05")
    #expect(TimeInterval(-150).minuteSecondClock == "-2:30")
  }

  /// Fractional seconds truncate toward zero, matching `Int(self)`.
  @Test func truncatesFractionalSeconds() {
    #expect(TimeInterval(185.9).minuteSecondClock == "3:05")
  }
}
