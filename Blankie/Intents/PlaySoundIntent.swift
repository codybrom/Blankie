//
//  PlaySoundIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

struct PlaySoundIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Play Sound" }
  static var description: IntentDescription {
    IntentDescription("Plays a sound on its own without changing your saved preset.")
  }

  @Parameter(
    title: "Sound",
    requestValueDialog: IntentDialog("Which sound would you like to play?")
  )
  var sound: SoundEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Play \(\.$sound)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    await AppSetup.ensureManagersReadyForIntents()
    guard let target = AudioManager.shared.sound(fileName: sound.id) else {
      throw BlankieIntentError.soundNotFound
    }
    // Saved shortcuts can still reference sounds excluded from Siri discovery.
    if target.isPresetUseOnly {
      return .result(dialog: IntentDialog("\(target.localizedTitle) is set to preset use only."))
    }
    let audio = AudioManager.shared
    audio.enterSingleSound(for: target)
    // Entering the same single sound is a no-op, so explicitly resume it if paused.
    audio.setGlobalPlaybackState(true)
    return .result(dialog: IntentDialog("Playing \(target.localizedTitle)."))
  }
}
