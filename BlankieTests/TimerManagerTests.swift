//
//  TimerManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The sleep-timer state machine, with expiry driven through the injected clock and tick().
//  Serialized: each test stops `TimerManager.shared` and restores the persisted selection.
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

  /// Anchoring to start plus duration keeps the end time from drifting between render ticks.
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

  @Test func startTimerPersistsSelection() {
    timer.selectedHours = 1
    timer.selectedMinutes = 15
    timer.startTimer(duration: 4500)
    #expect(UserDefaults.shared.integer(forKey: "timerLastSelectedHours") == 1)
    #expect(UserDefaults.shared.integer(forKey: "timerLastSelectedMinutes") == 15)
  }

  // MARK: - Expiry (injected clock and tick())

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

  /// The generation guard keeps a stale expiry task from pausing a re-armed timer.
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

  /// Adding time after the deferred pause is queued cancels it, like a re-arm.
  @Test func addTimeBeforeDeferredPauseIsNotCancelled() async {
    let t0 = Date(timeIntervalSince1970: 9000)
    timer.now = { t0 }
    audioManager.isGloballyPlaying = true

    timer.startTimer(duration: 600)
    timer.now = { t0.addingTimeInterval(601) }
    timer.tick()  // dispatches the expiry task
    timer.addTime(minutes: 5)

    for _ in 0..<100 { await Task.yield() }

    #expect(timer.isTimerActive, "the extended timer stays active")
    #expect(isClose(timer.remainingTime, 299, tol: 1.0))
    #expect(audioManager.isGloballyPlaying, "the queued expiry must not pause the extension")
  }
}
