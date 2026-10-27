//
//  VolumeIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// Blankie's app-wide volume. On iPhone and iPad it only applies with "Mix with
/// Other Audio" on (matching `NowPlayingSheet.volumeSlider`); otherwise the
/// hardware buttons own volume and the intent declines.
struct SetVolumeIntent: AppIntent {
  static var title: LocalizedStringResource { "Set Volume" }
  static var description: IntentDescription {
    IntentDescription("Sets Blankie's overall volume.")
  }

  @Parameter(title: "Volume", description: "0 to 100", inclusiveRange: (0, 100))
  var percent: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Set Blankie volume to \(\.$percent)%")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    #if os(iOS) || os(visionOS)
      guard GlobalSettings.shared.mixWithOthers else {
        return .result(
          dialog: IntentDialog(
            LocalizedStringResource(
              "volume.deviceControlled",
              defaultValue:
                "Volume is controlled by your device's volume buttons. Turn on Mix with Other Audio in Blankie's settings to set it here instead.",
              comment:
                "Shown via Siri when setting volume while Mix with Other Audio is off. Varies by device (iPhone/iPad)."
            )
          ))
      }
    #endif
    let clamped = min(max(percent, 0), 100)
    GlobalSettings.shared.setVolume(Double(clamped) / 100.0)
    let volumeText = (Double(clamped) / 100.0).formatted(.percent)
    return .result(dialog: IntentDialog("Volume set to \(volumeText)."))
  }
}

/// Per-sound mix level. The "Mix with Other Audio" gate above doesn't apply.
struct SetSoundVolumeIntent: AppIntent {
  static var title: LocalizedStringResource { "Set Sound Volume" }
  static var description: IntentDescription {
    IntentDescription("Sets the mix volume of a specific sound in Blankie.")
  }

  @Parameter(
    title: "Sound",
    requestValueDialog: IntentDialog("Which sound would you like to adjust?")
  )
  var sound: SoundEntity

  @Parameter(title: "Volume", description: "0 to 100", inclusiveRange: (0, 100))
  var percent: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Set \(\.$sound) volume to \(\.$percent)%")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    await AppSetup.ensureManagersReadyForIntents()
    guard let target = AudioManager.shared.sound(fileName: sound.id) else {
      throw BlankieIntentError.soundNotFound
    }
    let clamped = min(max(percent, 0), 100)
    target.volume = Float(clamped) / 100.0
    let volumeText = (Double(clamped) / 100.0).formatted(.percent)
    return .result(dialog: IntentDialog("\(target.localizedTitle) volume set to \(volumeText)."))
  }
}
