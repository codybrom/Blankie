//
//  PlaybackToggleValueIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents

/// Backs the Control Center play/pause toggle. `AudioPlaybackIntent`
/// conformance runs `perform()` in the app's process, same as the other
/// playback intents.
struct PlaybackToggleValueIntent: SetValueIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Toggle Blankie Playback" }

  @Parameter(title: "Playing")
  var value: Bool

  @MainActor
  func perform() async throws -> some IntentResult {
    await AppSetup.ensureManagersReadyForIntents()
    AudioManager.shared.setGlobalPlaybackState(value)
    return .result()
  }
}
