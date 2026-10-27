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

  // Plumbing the UI never reads, so it stays out of observation tracking.
  @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
  // Read by getEndTime() in view bodies, so it stays observation-tracked.
  private var startTime: Date?

  // Injectable clock. Tests override it and drive expiry through tick().
  @ObservationIgnored var now: () -> Date = { Date() }

  // Bumped on every start/stop/extend. handleTimerExpired's async stop and pause
  // checks it to skip a session that was cancelled or re-armed in the meantime.
  @ObservationIgnored private var expiryGeneration = 0

  private init() {
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

    UserDefaults.shared.set(selectedHours, forKey: "timerLastSelectedHours")
    UserDefaults.shared.set(selectedMinutes, forKey: "timerLastSelectedMinutes")

    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateTimer() }
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

  /// Advances the countdown one step using the injected clock. Production calls
  /// it from the 1 Hz timer. Tests call it directly.
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

    // Stop the countdown and pause in one main-actor task, so a progress tick
    // never sees the timer inactive while audio still plays (that re-anchors
    // the lock screen scrubber).
    let generation = expiryGeneration
    Task { @MainActor in
      // Skip if the timer was cancelled or re-armed since expiry.
      guard self.expiryGeneration == generation else { return }
      self.stopTimer()
      AudioManager.shared.setGlobalPlaybackState(false)
    }
  }

  func handleScenePhaseChange() {
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
    // Anchor to the fixed stop instant. `now + remainingTime` drifts with the
    // 1 Hz tick, so the "Stops at" label could flip between adjacent minutes.
    return startTime.addingTimeInterval(selectedDuration)
  }

  func addTime(minutes: Int) {
    guard isTimerActive else { return }
    // Extending at the instant of expiry must cancel the already-queued pause.
    expiryGeneration &+= 1
    remainingTime += TimeInterval(minutes * 60)
    selectedDuration += TimeInterval(minutes * 60)
  }

  deinit {
    timer?.invalidate()
  }
}
