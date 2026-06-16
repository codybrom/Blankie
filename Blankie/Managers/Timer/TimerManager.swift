//
//  TimerManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/29/25.
//

import Foundation
import Observation
import os

@Observable
class TimerManager {
  static let shared = TimerManager()

  var isTimerActive = false
  var remainingTime: TimeInterval = 0
  var selectedDuration: TimeInterval = 0
  var selectedHours: Int
  var selectedMinutes: Int

  // Plumbing the UI never reads; kept out of observation tracking.
  @ObservationIgnored private var timer: Timer?
  // Read by getEndTime() in view bodies, so it stays observation-tracked.
  private var startTime: Date?

  // Injectable clock. Production uses the wall clock; tests override it to drive
  // expiry deterministically via tick() instead of waiting on the 1 Hz timer.
  @ObservationIgnored var now: () -> Date = { Date() }

  // Bumped on every start/stop. handleTimerExpired dispatches its stop+pause
  // async (to batch them on the main actor); the generation lets that late task
  // detect a cancel or re-arm in the meantime and skip pausing the new session.
  @ObservationIgnored private var expiryGeneration = 0

  private init() {
    // Load saved duration or use defaults
    self.selectedHours = UserDefaults.shared.object(forKey: "timerLastSelectedHours") as? Int ?? 0
    self.selectedMinutes =
      UserDefaults.shared.object(forKey: "timerLastSelectedMinutes") as? Int ?? 30
  }

  func startTimer(duration: TimeInterval) {
    stopTimer()

    selectedDuration = duration
    remainingTime = duration
    startTime = now()
    isTimerActive = true

    // Save the user's selection for next time
    UserDefaults.shared.set(selectedHours, forKey: "timerLastSelectedHours")
    UserDefaults.shared.set(selectedMinutes, forKey: "timerLastSelectedMinutes")

    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateTimer()
    }

    Logger.audio.debug("TimerManager: Started timer for \(duration) seconds")
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
    expiryGeneration &+= 1
    isTimerActive = false
    remainingTime = 0
    selectedDuration = 0
    startTime = nil

    Logger.audio.debug("TimerManager: Timer stopped")
  }

  /// Advances the countdown one step using the injected clock. Exposed so tests
  /// can verify expiry (and the re-arm guard) deterministically without the
  /// 1 Hz run-loop timer; production drives this from that timer.
  func tick() { updateTimer() }

  private func updateTimer() {
    guard let startTime = startTime else { return }

    let elapsed = now().timeIntervalSince(startTime)
    remainingTime = max(0, selectedDuration - elapsed)

    if remainingTime <= 0 {
      handleTimerExpired()
    }
  }

  private func handleTimerExpired() {
    Logger.audio.debug("TimerManager: Timer expired")

    // Stop the countdown and pause together on the main actor. Doing the stop
    // synchronously (before this) let a 0.25s progress tick observe the
    // half-state — timer inactive but audio still "playing" — and re-anchor the
    // lock-screen scrubber to the loop position, a brief jump at expiry.
    let generation = expiryGeneration
    Task { @MainActor in
      // Skip if the timer was cancelled or re-armed between expiry and now,
      // otherwise we'd pause a session the user just started.
      guard self.expiryGeneration == generation else { return }
      self.stopTimer()
      AudioManager.shared.setGlobalPlaybackState(false)
    }
  }

  func handleScenePhaseChange() {
    // Update the timer when scene phase changes
    if isTimerActive {
      updateTimer()
    }
  }

  func formatRemainingTime() -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.zeroFormattingBehavior = .pad

    return formatter.string(from: remainingTime) ?? "0:00"
  }

  func getEndTime() -> Date? {
    guard isTimerActive, let startTime else { return nil }
    // Anchor to the fixed stop instant (start + duration). Re-deriving
    // `now + remainingTime` each render drifts by the sub-second gap between
    // the 1 Hz tick and the render, so a stop time near a minute boundary makes
    // the "Stops/Pausing at" label flash between adjacent minutes.
    return startTime.addingTimeInterval(selectedDuration)
  }

  func addTime(minutes: Int) {
    guard isTimerActive else { return }
    remainingTime += TimeInterval(minutes * 60)
    selectedDuration += TimeInterval(minutes * 60)
  }

  deinit {
    stopTimer()
  }
}
