//
//  PlayPresetIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

struct PlayPresetIntent: AppIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Play Preset" }
  static var description: IntentDescription {
    IntentDescription("Applies a Blankie preset and starts playing its sounds.")
  }

  @Parameter(
    title: "Preset",
    requestValueDialog: IntentDialog("Which preset would you like to play?")
  )
  var preset: PresetEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Play \(\.$preset)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let target = PresetManager.shared.presets.first(where: { $0.id == preset.id }) else {
      throw BlankieIntentError.presetNotFound
    }
    try PresetManager.shared.applyPreset(target)
    // applyPreset no-ops playback when the preset was already current, so
    // explicitly ensure it's playing regardless of prior state.
    AudioManager.shared.setGlobalPlaybackState(true)
    return .result(dialog: IntentDialog("Playing \(target.displayName)."))
  }
}
