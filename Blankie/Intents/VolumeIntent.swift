//
//  VolumeIntent.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// Blankie's overall/app-wide volume. On iPhone and iPad this only has a UI
/// (and a real effect distinct from the hardware volume) when "Mix with
/// Other Audio" is on — otherwise the system volume buttons are the only
/// volume control, matching `NowPlayingSheet.volumeSlider`. This intent
/// mirrors that gate rather than silently changing a value with no on-screen
/// slider to see or undo it.
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
            "Volume is controlled by your device's volume buttons on iPhone and iPad. Turn on Mix with Other Audio in Blankie's settings to set it here instead."
          ))
      }
    #endif
    let clamped = min(max(percent, 0), 100)
    GlobalSettings.shared.setVolume(Double(clamped) / 100.0)
    return .result(dialog: IntentDialog("Volume set to \(clamped)%."))
  }
}

/// Per-sound volume, unrestricted by the "Mix with Other Audio" gate above —
/// this adjusts the sound's own mix level, not the device/app-wide output.
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
    guard let target = AudioManager.shared.sound(fileName: sound.id) else {
      throw BlankieIntentError.soundNotFound
    }
    let clamped = min(max(percent, 0), 100)
    target.volume = Float(clamped) / 100.0
    return .result(dialog: IntentDialog("\(target.localizedTitle) volume set to \(clamped)%."))
  }
}
