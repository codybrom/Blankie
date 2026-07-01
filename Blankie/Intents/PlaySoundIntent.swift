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
    IntentDescription("Adds a sound to the current mix and starts playing it.")
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
    guard let target = AudioManager.shared.sound(fileName: sound.id) else {
      throw BlankieIntentError.soundNotFound
    }
    if !target.isSelected {
      target.isSelected = true
    }
    AudioManager.shared.setGlobalPlaybackState(true)
    return .result(dialog: IntentDialog("Playing \(target.localizedTitle)."))
  }
}
