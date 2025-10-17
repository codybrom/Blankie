//
//  GlobalSettings+Initialization.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import Foundation
import SwiftUI

extension GlobalSettings {
  func loadBasicSettings() {
    // Initialize properties directly
    let savedVolume = UserDefaults.shared.double(forKey: UserDefaultsKeys.volume)
    volume = savedVolume == 0 ? 1.0 : savedVolume

    appearance =
      UserDefaults.shared.string(forKey: UserDefaultsKeys.appearance)
        .flatMap { AppearanceMode(rawValue: $0) } ?? .system

    // Load saved accent color
    if let colorString = UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor) {
      customAccentColor = Color(fromString: colorString)
    } else {
      customAccentColor = nil
    }

    // Default to false for autoPlayOnLaunch if not set (safer default)
    autoPlayOnLaunch =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.autoPlayOnLaunch) as? Bool ?? false

    // Hide inactive sounds preference
    hideInactiveSounds = UserDefaults.shared.bool(forKey: UserDefaultsKeys.hideInactiveSounds)

    // Show labels preference (default to true)
    showSoundNames =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showSoundNames) as? Bool ?? true

    // Icon size preference (default to medium)
    if let savedSize = UserDefaults.shared.string(forKey: UserDefaultsKeys.iconSize),
       let size = IconSize(rawValue: savedSize)
    {
      iconSize = size
    } else {
      iconSize = .medium
    }

    // Show list view preference (default to false - grid view)
    showingListView = UserDefaults.shared.bool(forKey: UserDefaultsKeys.showingListView)

    // Show progress border preference (default to false)
    showProgressBorder =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showProgressBorder) as? Bool ?? false

    // Lock portrait orientation on iOS preference (default to false)
    lockPortraitOrientationiOS =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.lockPortraitOrientationiOS) as? Bool
        ?? false

    // Load Quick Mix sound file names (default to original 8 sounds)
    if let savedQuickMixSounds = UserDefaults.shared.array(
      forKey: UserDefaultsKeys.quickMixSoundFileNames) as? [String]
    {
      quickMixSoundFileNames = savedQuickMixSounds
    }

    lockScreenBackgroundEnabled =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.lockScreenBackgroundEnabled) as? Bool
        ?? true
  }

  func loadPlatformSettings() {
    // Load platform-specific preferences
    enableSpatialAudio =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.enableSpatialAudio) as? Bool ?? false
    mixWithOthers =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.mixWithOthers) as? Bool ?? false
    volumeWithOtherAudio =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.volumeWithOtherAudio) as? Double ?? 0.5
  }

  func loadLanguageSettings() {
    // First initialize language with default value
    language = Language.system

    // Then load available languages
    availableLanguages = Language.getAvailableLanguages()

    // Finally, try to set the saved language preference
    let savedLanguageCode = UserDefaults.shared.string(forKey: UserDefaultsKeys.language)
    if let code = savedLanguageCode,
       let savedLanguage = availableLanguages.first(where: { $0.code == code })
    {
      language = savedLanguage
    }
  }

  func migrateLegacySettings() {
    // Migration: Convert old alwaysStartPaused setting to new autoPlayOnLaunch setting
    if let oldValue = UserDefaults.shared.object(forKey: "alwaysStartPaused") as? Bool {
      print(
        "🔄 GlobalSettings: Migrating alwaysStartPaused(\(oldValue)) to autoPlayOnLaunch(\(!oldValue))"
      )
      autoPlayOnLaunch = !oldValue // Flip the logic
      UserDefaults.shared.set(autoPlayOnLaunch, forKey: UserDefaultsKeys.autoPlayOnLaunch)
      UserDefaults.shared.removeObject(forKey: "alwaysStartPaused") // Remove old key
    }
  }
}
