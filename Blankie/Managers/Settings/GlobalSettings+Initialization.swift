//
//  GlobalSettings+Initialization.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import Foundation
import SwiftUI
import os

extension GlobalSettings {
  func loadBasicSettings() {
    // object(forKey:) to distinguish "never saved" (default 1.0) from a saved
    // zero — double(forKey:) returns 0 for both, which forced a zeroed volume
    // back to full on every launch.
    volume = UserDefaults.shared.object(forKey: UserDefaultsKeys.volume) as? Double ?? 1.0

    // Load saved accent color
    if let colorString = UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor) {
      customAccentColor = Color(fromString: colorString)
    } else {
      customAccentColor = nil
    }

    // Autoplay is macOS-only (stored under autoPlayOnLaunchMac); on first launch
    // after the rename, carry the legacy autoPlayOnLaunch value forward.
    #if os(macOS)
      if let mac = UserDefaults.shared.object(forKey: UserDefaultsKeys.autoPlayOnLaunchMac) as? Bool
      {
        autoPlayOnLaunch = mac
      } else if let legacy = UserDefaults.shared.object(forKey: UserDefaultsKeys.autoPlayOnLaunch)
        as? Bool
      {
        autoPlayOnLaunch = legacy
        UserDefaults.shared.set(legacy, forKey: UserDefaultsKeys.autoPlayOnLaunchMac)
      } else {
        autoPlayOnLaunch = false
      }
    #else
      autoPlayOnLaunch = false
    #endif

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

    // Show progress border preference (default to true)
    showProgressBorder =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showProgressBorder) as? Bool ?? true

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

    // Load favorited presets (the `starredItems` token list). Nothing is
    // favorited by default — the initializer seeds an empty array.
    if let savedStarred = UserDefaults.shared.array(
      forKey: UserDefaultsKeys.starredItems) as? [String]
    {
      starredItems = savedStarred
    }

    lockScreenBackgroundEnabled =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.lockScreenBackgroundEnabled) as? Bool
      ?? true

    // Dock icon pause badge (macOS), default on.
    showDockBadgeWhenPaused =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showDockBadgeWhenPaused) as? Bool ?? true

    // Menu bar (macOS): show the icon (default on); the Dock-hiding modes off.
    showMenuBarIcon =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showMenuBarIcon) as? Bool ?? true
    menuBarOnlyMode =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.menuBarOnlyMode) as? Bool ?? false
    hideDockWhenWindowClosed =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.hideDockWhenWindowClosed) as? Bool
      ?? false

    // Library section collapse state (default expanded).
    librarySoundsExpanded =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.librarySoundsExpanded) as? Bool ?? true
    libraryPresetsExpanded =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.libraryPresetsExpanded) as? Bool ?? true

    // App-wide default lock screen animation (used when a preset has none).
    if let data = UserDefaults.shared.data(forKey: UserDefaultsKeys.defaultLockScreenArtwork),
      let ref = try? JSONDecoder().decode(AnimatedArtworkRef.self, from: data)
    {
      defaultLockScreenArtwork = ref
    }

    // Background blur (default on). Read via `object` rather than
    // `double(forKey:)` so a deliberately-saved 0 ("no blur") isn't mistaken
    // for "unset" and reset back to the default. Blur is now on/off, so
    // migrate any legacy radius (e.g. the old "High" 15) to the single value.
    let loadedBlur =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.backgroundBlurRadius) as? Double
    let normalizedBlur =
      (loadedBlur ?? defaultBackgroundBlurRadius) > 0
      ? defaultBackgroundBlurRadius : 0
    backgroundBlurRadius = normalizedBlur
    if let loadedBlur, loadedBlur != normalizedBlur {
      UserDefaults.shared.set(normalizedBlur, forKey: UserDefaultsKeys.backgroundBlurRadius)
    }
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
    #if os(macOS)
      // `alwaysStartPaused` is a legacy key that predates `autoPlayOnLaunch` and stores the opposite
      // value. When present, its inverse overrides the value loadBasicSettings
      // already carried forward.
      if let oldValue = UserDefaults.shared.object(forKey: "alwaysStartPaused") as? Bool {
        autoPlayOnLaunch = !oldValue
        UserDefaults.shared.set(autoPlayOnLaunch, forKey: UserDefaultsKeys.autoPlayOnLaunchMac)
        UserDefaults.shared.removeObject(forKey: "alwaysStartPaused")
      }
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.autoPlayOnLaunch)
    #endif
    // iOS purges the legacy autoplay keys via AppDataMigrator's obsoleteKeys.
  }
}
