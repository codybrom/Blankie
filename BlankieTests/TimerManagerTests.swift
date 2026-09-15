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
  private let audioManager = AudioManager.shared

  init() {
    timer.stopTimer()
    audioManager.isGloballyPlaying = false
  }
  isolated deinit {
    timer.stopTimer()
    timer.now = { Date() }  // restore the real clock for other suites
    audioManager.isGloballyPlaying = false
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

  // MARK: - Expiry (deterministic via the injected clock + tick())

  /// Reaching zero deactivates the timer AND pauses global playback — the sleep
  /// timer's entire purpose. Driven via the injected clock so it's deterministic
  /// instead of waiting on the 1 Hz run-loop timer.
  @Test func expiryStopsTimerAndPausesAudio() async {
    let t0 = Date(timeIntervalSince1970: 1000)
    timer.now = { t0 }
    audioManager.isGloballyPlaying = true

    timer.startTimer(duration: 600)
    timer.now = { t0.addingTimeInterval(601) }
    timer.tick()  // expiry dispatches a main-actor stop+pause task

    for _ in 0..<100 where timer.isTimerActive { await Task.yield() }

    #expect(!timer.isTimerActive)
    #expect(timer.remainingTime == 0)
    #expect(!audioManager.isGloballyPlaying, "expiry pauses playback")
  }

  /// remainingTime tracks the clock and clamps to zero (never negative).
  @Test func tickCountsDownAndClampsAtZero() async {
    let t0 = Date(timeIntervalSince1970: 5000)
    timer.now = { t0 }
    timer.startTimer(duration: 600)

    timer.now = { t0.addingTimeInterval(100) }
    timer.tick()
    #expect(isClose(timer.remainingTime, 500, tol: 1.0))

    timer.now = { t0.addingTimeInterval(10_000) }
    timer.tick()
    #expect(timer.remainingTime == 0)

    for _ in 0..<100 where timer.isTimerActive { await Task.yield() }  // drain expiry task
  }

  /// A timer re-armed between expiry and the deferred pause task must NOT be
  /// paused by that stale task (the generation guard).
  @Test func reArmBeforeDeferredPauseIsNotCancelled() async {
    let t0 = Date(timeIntervalSince1970: 8000)
    timer.now = { t0 }
    audioManager.isGloballyPlaying = true

    timer.startTimer(duration: 600)
    timer.now = { t0.addingTimeInterval(601) }
    timer.tick()  // dispatches the stale expiry task (captures the old generation)
    timer.startTimer(duration: 600)  // re-arm synchronously bumps the generation

    for _ in 0..<100 { await Task.yield() }

    #expect(timer.isTimerActive, "the re-armed timer stays active")
    #expect(
      audioManager.isGloballyPlaying, "the stale expiry task must not pause the new session")
  }
}
