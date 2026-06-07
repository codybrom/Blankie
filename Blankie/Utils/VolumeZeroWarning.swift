//
//  VolumeZeroWarning.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/26.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// Launch-time "volume is all the way down" warning, mirroring Music.app's.
/// macOS warns when the app volume slider is at zero; iOS warns when Mix With
/// Other Audio is on but Blankie's volume with media is zero (both silent).
enum VolumeZeroWarning {
  private static let suppressKey = "suppressVolumeZeroWarning"
  private static var hasShownThisLaunch = false

  /// The zeroed-volume state holds, once per launch, unless opted out.
  @MainActor
  static func shouldWarn() -> Bool {
    guard !hasShownThisLaunch,
      !UserDefaults.standard.bool(forKey: suppressKey)
    else { return false }
    #if os(macOS)
      return GlobalSettings.shared.volume == 0
    #else
      return GlobalSettings.shared.mixWithOthers
        && GlobalSettings.shared.volumeWithOtherAudio == 0
    #endif
  }

  static func markShown() {
    hasShownThisLaunch = true
  }

  static func suppress() {
    UserDefaults.standard.set(true, forKey: suppressKey)
  }

  #if os(macOS)
    /// Native alert with the suppression checkbox, like Music.app's.
    @MainActor
    static func showIfNeeded() {
      guard shouldWarn() else { return }
      markShown()

      let alert = NSAlert()
      alert.messageText = String(
        localized: "The Blankie volume is currently turned all the way down.")
      alert.informativeText = String(
        localized: "To change the volume, drag the slider at the bottom of the Blankie window.")
      alert.showsSuppressionButton = true
      alert.suppressionButton?.title = String(localized: "Don't warn again")
      alert.addButton(withTitle: String(localized: "OK"))
      alert.runModal()

      if alert.suppressionButton?.state == .on {
        suppress()
      }
    }
  #endif
}
