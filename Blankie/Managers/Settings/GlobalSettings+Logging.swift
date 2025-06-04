//
//  GlobalSettings+Logging.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Foundation

extension GlobalSettings {
  func logCurrentSettings() {
    print("\n⚙️ GlobalSettings: Current State")
    print("  - Volume: \(volume)")
    print("  - Appearance: \(appearance.rawValue)")
    print("  - Custom Accent Color: \(customAccentColor?.toString ?? "System")")
    print("  - Autoplay When Opened: \(autoPlayOnLaunch)")
    print("  - Hide Inactive Sounds: \(hideInactiveSounds)")
    print("  - Enable Haptics: \(enableHaptics)")
    print("  - Enable Spatial Audio: \(enableSpatialAudio)")
    print("  - Mix With Others: \(mixWithOthers)")
    print("  - Volume With Other Audio: \(volumeWithOtherAudio)")
    print("  - Language: \(language.code)")
    print("  - Available Languages: \(availableLanguages.map { $0.code }.joined(separator: ", "))")
  }
}
