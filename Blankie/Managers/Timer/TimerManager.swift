//
//  TimerManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/29/25.
//

import Combine
import Foundation

class TimerManager: ObservableObject {
  static let shared = TimerManager()

  @Published var isTimerActive = false
  @Published var remainingTime: TimeInterval = 0
  @Published var selectedDuration: TimeInterval = 0
  @Published var selectedHours: Int
  @Published var selectedMinutes: Int

  private var timer: Timer?
  private var startTime: Date?
  private var cancellables = Set<AnyCancellable>()

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
    startTime = Date()
    isTimerActive = true

    // Save the user's selection for next time
    UserDefaults.shared.set(selectedHours, forKey: "timerLastSelectedHours")
    UserDefaults.shared.set(selectedMinutes, forKey: "timerLastSelectedMinutes")

    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateTimer()
    }

    debugLog("⏱️ TimerManager: Started timer for \(duration) seconds")
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
    isTimerActive = false
    remainingTime = 0
    selectedDuration = 0
    startTime = nil

    debugLog("⏱️ TimerManager: Timer stopped")
  }

  private func updateTimer() {
    guard let startTime = startTime else { return }

    let elapsed = Date().timeIntervalSince(startTime)
    remainingTime = max(0, selectedDuration - elapsed)

    if remainingTime <= 0 {
      handleTimerExpired()
    }
  }

  private func handleTimerExpired() {
    debugLog("⏱️ TimerManager: Timer expired")

    stopTimer()

    Task { @MainActor in
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
    guard isTimerActive else { return nil }
    return Date().addingTimeInterval(remainingTime)
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
