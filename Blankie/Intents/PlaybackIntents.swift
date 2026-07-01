//
//  PlaybackIntents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// Resumes playback of the current mix. Deterministic "get sound going"
/// intent for Siri — distinct from `ToggleBlankiePlaybackIntent`, which can
/// pause depending on current state and is a poor match for a "Play" phrase.
struct PlayBlankieIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Play" }
  static var description: IntentDescription {
    IntentDescription("Resumes playback of the current Blankie mix.")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared
    guard audio.hasSelectedSounds || audio.soloModeSound != nil else {
      return .result(dialog: IntentDialog("Select some sounds in Blankie first."))
    }
    audio.setGlobalPlaybackState(true)
    return .result(dialog: IntentDialog("Playing."))
  }
}

struct PauseBlankieIntent: AppIntent {
  static var title: LocalizedStringResource { "Pause" }
  static var description: IntentDescription { IntentDescription("Pauses Blankie's playback.") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AudioManager.shared.setGlobalPlaybackState(false)
    return .result(dialog: IntentDialog("Paused."))
  }
}

struct ToggleBlankiePlaybackIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Toggle Playback" }
  static var description: IntentDescription {
    IntentDescription("Plays Blankie if it's paused, or pauses it if it's playing.")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared
    audio.togglePlayback()
    return .result(
      dialog: audio.isGloballyPlaying ? IntentDialog("Playing.") : IntentDialog("Paused."))
  }
}
