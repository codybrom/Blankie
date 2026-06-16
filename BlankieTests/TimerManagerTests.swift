//
//  TimerManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The sleep-timer state machine. Synchronous transitions and the fixed-anchor
//  end time (guards the "Stops at HH:MM" minute-boundary flicker). The 1 Hz
//  expiry tick is integration territory (no injectable clock) and is not driven.
//
//  Serialized + main-actor: drives the `TimerManager.shared` singleton and
//  schedules a run-loop timer; each test stops it and restores the persisted
//  selection in `deinit`.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class TimerManagerTests {
  private let snapshot = DefaultsSnapshot(["timerLastSelectedHours", "timerLastSelectedMinutes"])
  private let timer = TimerManager.shared

  init() { timer.stopTimer() }
  deinit {
    timer.stopTimer()
    snapshot.restore()
  }

  @Test func startTimerActivatesWithDuration() {
    timer.startTimer(duration: 600)
    #expect(timer.isTimerActive)
    #expect(isClose(timer.remainingTime, 600, tol: 1.0))
    #expect(isClose(timer.selectedDuration, 600, tol: 1.0))
  }

  /// The end time anchors to start+duration (not now+remaining), so it doesn't
  /// drift between render ticks.
  @Test func endTimeAnchorsToStartPlusDuration() {
    #expect(timer.getEndTime() == nil)  // inactive

    timer.startTimer(duration: 600)
    let end = try! #require(timer.getEndTime())
    #expect(isClose(end.timeIntervalSinceNow, 600, tol: 2.0))
  }

  @Test func addTimeExtendsRemainingAndDuration() {
    timer.startTimer(duration: 300)
    timer.addTime(minutes: 5)
    #expect(isClose(timer.remainingTime, 600, tol: 1.0))
    #expect(isClose(timer.selectedDuration, 600, tol: 1.0))
  }

  /// addTime is a no-op when no timer is running.
  @Test func addTimeIgnoredWhenInactive() {
    timer.addTime(minutes: 10)
    #expect(!timer.isTimerActive)
    #expect(timer.remainingTime == 0)
  }

  @Test func stopTimerClearsState() {
    timer.startTimer(duration: 600)
    timer.stopTimer()
    #expect(!timer.isTimerActive)
    #expect(timer.remainingTime == 0)
    #expect(timer.selectedDuration == 0)
    #expect(timer.getEndTime() == nil)
  }

  /// Starting a timer persists the selection for next launch.
  @Test func startTimerPersistsSelection() {
    timer.selectedHours = 1
    timer.selectedMinutes = 15
    timer.startTimer(duration: 4500)
    #expect(UserDefaults.shared.integer(forKey: "timerLastSelectedHours") == 1)
    #expect(UserDefaults.shared.integer(forKey: "timerLastSelectedMinutes") == 15)
  }
}
