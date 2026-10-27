//
//  WidgetToggleQuickMixSoundIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents

/// Toggles one sound in the Quick Mix widget. Like CarPlay's `QuickMixGridTemplate`,
/// it enters Quick Mix with the tapped sound when Quick Mix isn't active.
struct WidgetToggleQuickMixSoundIntent: AppIntent, AudioPlaybackIntent {
  static var isDiscoverable: Bool { false }

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

    // While paused, a tap resumes playback and never deselects (the same rule
    // regular sound tiles follow).
    guard audio.isGloballyPlaying else {
      audio.toggleOrResume(target)
      return .result()
    }

    audio.toggleQuickMixSound(target)
    return .result()
  }
}

/// Applies a relative change to the live value, so rapid widget taps accumulate
/// even when the widget's timeline is out of date.
struct WidgetAdjustQuickMixVolumeIntent: AppIntent, AudioPlaybackIntent {
  static var isDiscoverable: Bool { false }
  static var title: LocalizedStringResource { "Set Sound Volume" }

  @Parameter(title: "Sound") var fileName: String
  @Parameter(title: "Volume") var deltaPercent: Int

  init() {}
  init(fileName: String, deltaPercent: Int) {
    self.fileName = fileName
    self.deltaPercent = deltaPercent
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    await AppSetup.ensureManagersReadyForIntents()
    AudioManager.shared.adjustQuickMixSoundVolume(fileName: fileName, deltaPercent: deltaPercent)
    return .result()
  }
}
