//
//  SleepTimerIntents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

struct StartSleepTimerIntent: AppIntent {
  static var title: LocalizedStringResource { "Start Sleep Timer" }
  static var description: IntentDescription {
    IntentDescription("Starts a sleep timer that pauses Blankie when it ends.")
  }

  @Parameter(title: "Minutes", description: "Minutes from now", inclusiveRange: (1, 480))
  var minutes: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Stop Blankie in \(\.$minutes) minutes")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let clamped = min(max(minutes, 1), 480)
    TimerManager.shared.startTimer(duration: TimeInterval(clamped * 60))
    return .result(dialog: IntentDialog("Sleep timer set for \(clamped) minutes."))
  }
}

struct StopSleepTimerIntent: AppIntent {
  static var title: LocalizedStringResource { "Stop Sleep Timer" }
  static var description: IntentDescription {
    IntentDescription("Cancels Blankie's sleep timer.")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard TimerManager.shared.isTimerActive else {
      return .result(dialog: IntentDialog("There's no sleep timer running."))
    }
    TimerManager.shared.stopTimer()
    return .result(dialog: IntentDialog("Sleep timer cancelled."))
  }
}
