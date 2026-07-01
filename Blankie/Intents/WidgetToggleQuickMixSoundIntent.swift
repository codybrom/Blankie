//
//  WidgetToggleQuickMixSoundIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents

/// Toggles one sound in/out of Quick Mix from the dedicated Quick Mix
/// widget's grid — mirrors CarPlay's `QuickMixGridTemplate`, which enters
/// Quick Mix with the tapped sound if it isn't already active, or toggles
/// that sound within an already-active mix.
struct WidgetToggleQuickMixSoundIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Toggle Quick Mix Sound" }
  static var description: IntentDescription {
    IntentDescription("Adds or removes a sound from Blankie's Quick Mix.")
  }

  @Parameter(title: "Sound")
  var fileName: String

  init() {}

  /// Explicit init: the synthesized memberwise init for a `@Parameter`
  /// property doesn't accept its plain wrapped-value type here.
  init(fileName: String) {
    self.fileName = fileName
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    await AppSetup.ensureManagersReadyForIntents()
    let audio = AudioManager.shared
    guard let target = audio.sound(fileName: fileName) else {
      throw BlankieIntentError.soundNotFound
    }

    guard audio.isQuickMix else {
      audio.enterQuickMix(with: [target])
      return .result()
    }

    // Paused: any tap should get sound going, never read as "deselect" —
    // the same tap-to-resume rule regular sound tiles use
    // (`AudioManager.toggleOrResume`). Without this, tapping an
    // already-selected-but-paused sound would just toggle it off.
    guard audio.isGloballyPlaying else {
      if !target.isSelected {
        target.isSelected = true
      }
      audio.setGlobalPlaybackState(true)
      return .result()
    }

    audio.toggleQuickMixSound(target)
    return .result()
  }
}
