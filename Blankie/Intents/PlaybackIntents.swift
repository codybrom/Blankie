//
//  PlaybackIntents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

// Widget buttons use WidgetSetPlaybackIntent. Keep the public Play, Pause and
// Toggle Playback actions out of the extension's catalog so it cannot advertise
// duplicate actions.
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

#endif

/// A widget's play or pause button. The direction comes from the snapshot the
/// widget drew, so a Pause left showing after the app was killed can't start
/// audio in the cold-launched app, as a toggle would.
struct WidgetSetPlaybackIntent: AppIntent, AudioPlaybackIntent {
  static var isDiscoverable: Bool { false }

  static var title: LocalizedStringResource { "Set Playback" }

  @Parameter(title: "Play")
  var play: Bool

  init() {}

  init(play: Bool) {
    self.play = play
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    await AppSetup.ensureManagersReadyForIntents()
    AudioManager.shared.setGlobalPlaybackState(play)
    return .result()
  }
}
