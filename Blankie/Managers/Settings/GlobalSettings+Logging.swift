//
//  GlobalSettings+Logging.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Foundation

extension GlobalSettings {
  func logCurrentSettings() {
    debugLog("\n⚙️ GlobalSettings: Current State")
    debugLog("  - Volume: \(volume)")
    debugLog("  - Appearance: \(appearance.rawValue)")
    debugLog("  - Custom Accent Color: \(customAccentColor?.toString ?? "System")")
    debugLog("  - Autoplay on Open: \(autoPlayOnLaunch)")
    debugLog("  - Enable Spatial Audio: \(enableSpatialAudio)")
    debugLog("  - Mix With Others: \(mixWithOthers)")
    debugLog("  - Volume With Other Audio: \(volumeWithOtherAudio)")
    debugLog("  - Lock Screen Background Enabled: \(lockScreenBackgroundEnabled)")
    debugLog("  - Language: \(language.code)")
    debugLog(
      "  - Available Languages: \(availableLanguages.map { $0.code }.joined(separator: ", "))")
  }
}
