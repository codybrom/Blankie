//
//  PlaybackIntents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

// Only Toggle Playback is used by widget buttons. Keep app-only Play/Pause
// out of the extension's action catalog so it cannot advertise duplicate actions.
#if !WIDGET_EXTENSION
  /// Resumes playback of the current mix. Siri's "Play" phrases use this because
  /// `ToggleBlankiePlaybackIntent` can pause, depending on state.
  struct PlayBlankieIntent: AppIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Play" }
    static var description: IntentDescription {
      IntentDescription("Resumes playback of the current Blankie mix.")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
      await AppSetup.ensureManagersReadyForIntents()
      let audio = AudioManager.shared
      guard audio.hasPlayableSelection else {
        return .result(dialog: IntentDialog("Select some sounds in Blankie first."))
      }
      audio.setGlobalPlaybackState(true)
      return .result(dialog: IntentDialog("Playing."))
    }
  }

  struct PauseBlankieIntent: AppIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Pause" }
    static var description: IntentDescription { IntentDescription("Pauses Blankie's playback.") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
      await AppSetup.ensureManagersReadyForIntents()
      AudioManager.shared.setGlobalPlaybackState(false)
      return .result(dialog: IntentDialog("Paused."))
    }
  }

#endif

struct ToggleBlankiePlaybackIntent: AppIntent, AudioPlaybackIntent {
  #if WIDGET_EXTENSION
    // The app exposes the public action. The extension only renders its button.
    static var isDiscoverable: Bool { false }
  #endif

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
