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
    // object(forKey:) tells "never saved" (default 1.0) from a saved zero,
    // since double(forKey:) returns 0 for both.
    volume = UserDefaults.shared.object(forKey: UserDefaultsKeys.volume) as? Double ?? 1.0

    if let colorString = UserDefaults.shared.string(forKey: UserDefaultsKeys.accentColor) {
      customAccentColor = Color(fromString: colorString)
    } else {
      customAccentColor = nil
    }

    // Autoplay is macOS-only (stored under autoPlayOnLaunchMac). On first launch
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

    showSoundNames =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showSoundNames) as? Bool ?? true

    if let savedSize = UserDefaults.shared.string(forKey: UserDefaultsKeys.iconSize),
      let size = IconSize(rawValue: savedSize)
    {
      iconSize = size
    } else {
      iconSize = .medium
    }

    showingListView = UserDefaults.shared.bool(forKey: UserDefaultsKeys.showingListView)

    showProgressBorder =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showProgressBorder) as? Bool ?? true

    showPlaybackAsContinuous =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showPlaybackAsContinuous) as? Bool ?? true

    lockPortraitOrientationiOS =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.lockPortraitOrientationiOS) as? Bool
      ?? false

    nowPlayingFirst =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.nowPlayingFirst) as? Bool ?? true

    if let savedQuickMixSounds = UserDefaults.shared.array(
      forKey: UserDefaultsKeys.quickMixSoundFileNames) as? [String]
    {
      quickMixSoundFileNames = savedQuickMixSounds
    }

    if let savedStarred = UserDefaults.shared.array(
      forKey: UserDefaultsKeys.starredItems) as? [String]
    {
      starredItems = savedStarred
    }

    lockScreenBackgroundEnabled =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.lockScreenBackgroundEnabled) as? Bool
      ?? true

    showDockBadgeWhenPaused =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showDockBadgeWhenPaused) as? Bool ?? true

    showMenuBarIcon =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showMenuBarIcon) as? Bool ?? true
    menuBarOnlyMode =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.menuBarOnlyMode) as? Bool ?? false
    hideDockWhenWindowClosed =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.hideDockWhenWindowClosed) as? Bool
      ?? false

    librarySoundsExpanded =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.librarySoundsExpanded) as? Bool ?? true
    libraryPresetsExpanded =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.libraryPresetsExpanded) as? Bool ?? true

    if let data = UserDefaults.shared.data(forKey: UserDefaultsKeys.defaultLockScreenArtwork),
      let ref = try? JSONDecoder().decode(AnimatedArtworkRef.self, from: data)
    {
      defaultLockScreenArtwork = ref
    }

    // object(forKey:) keeps a saved 0 ("no blur") distinct from unset. Blur is
    // on/off, so any legacy radius normalizes to the single default value.
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
    enableSpatialAudio =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.enableSpatialAudio) as? Bool ?? false
    mixWithOthers =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.mixWithOthers) as? Bool ?? false
    volumeWithOtherAudio =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.volumeWithOtherAudio) as? Double ?? 0.5
  }

  func loadLanguageSettings() {
    language = Language.system

    availableLanguages = Language.getAvailableLanguages()

    let savedLanguageCode = UserDefaults.shared.string(forKey: UserDefaultsKeys.language)
    if let code = savedLanguageCode,
      let savedLanguage = availableLanguages.first(where: { $0.code == code })
    {
      language = savedLanguage
    }
  }

  func migrateLegacySettings() {
    #if os(macOS)
      // Legacy `alwaysStartPaused` stores the inverse of autoplay. When present,
      // it overrides the value loadBasicSettings carried forward.
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
