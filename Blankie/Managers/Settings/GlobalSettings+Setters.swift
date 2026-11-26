//
//  GlobalSettings+Setters.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import Foundation
import SwiftUI
import os

extension GlobalSettings {
  @MainActor
  func setAccentColor(_ newColor: Color?) {
    customAccentColor = newColor
    if let color = newColor {
      UserDefaults.shared.set(color.toString, forKey: UserDefaultsKeys.accentColor)
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.accentColor)
    }
    logCurrentSettings()
    AudioManager.shared.republishWidgetCatalog()
  }

  /// macOS-only and stored under the platform-scoped autoPlayOnLaunchMac key.
  @MainActor
  func setAutoPlayOnLaunch(_ value: Bool) {
    autoPlayOnLaunch = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.autoPlayOnLaunchMac)
    logCurrentSettings()
  }

  @MainActor
  func setShowSoundNames(_ value: Bool) {
    showSoundNames = value
    UserDefaults.shared.set(showSoundNames, forKey: UserDefaultsKeys.showSoundNames)
    logCurrentSettings()
  }

  @MainActor
  func setIconSize(_ value: IconSize) {
    iconSize = value
    UserDefaults.shared.set(iconSize.rawValue, forKey: UserDefaultsKeys.iconSize)
    logCurrentSettings()
  }

  @MainActor
  func setShowingListView(_ value: Bool) {
    showingListView = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.showingListView)
    logCurrentSettings()
  }

  @MainActor
  func setShowProgressBorder(_ value: Bool) {
    showProgressBorder = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.showProgressBorder)
    logCurrentSettings()
  }

  @MainActor
  func setLibrarySoundsExpanded(_ value: Bool) {
    librarySoundsExpanded = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.librarySoundsExpanded)
  }

  @MainActor
  func setLibraryPresetsExpanded(_ value: Bool) {
    libraryPresetsExpanded = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.libraryPresetsExpanded)
  }

  @MainActor
  func setLastSeenHighlightsVersion(_ version: String) {
    guard lastSeenHighlightsVersion != version else { return }
    lastSeenHighlightsVersion = version
    UserDefaults.shared.set(version, forKey: UserDefaultsKeys.lastSeenHighlightsVersion)
  }

  @MainActor
  func setShowDockBadgeWhenPaused(_ value: Bool) {
    showDockBadgeWhenPaused = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.showDockBadgeWhenPaused)
    logCurrentSettings()
  }

  @MainActor
  func setShowPlaybackAsContinuous(_ value: Bool) {
    showPlaybackAsContinuous = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.showPlaybackAsContinuous)
    AudioManager.shared.nowPlayingManager?.republishCurrentPreset()
  }

  @MainActor
  func setShowMenuBarIcon(_ value: Bool) {
    showMenuBarIcon = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.showMenuBarIcon)
    // The Dock-hiding modes need the menu bar icon as the way back, so clear
    // them when it's off.
    if !value {
      menuBarOnlyMode = false
      UserDefaults.shared.set(false, forKey: UserDefaultsKeys.menuBarOnlyMode)
      hideDockWhenWindowClosed = false
      UserDefaults.shared.set(false, forKey: UserDefaultsKeys.hideDockWhenWindowClosed)
    }
    logCurrentSettings()
  }

  @MainActor
  func setMenuBarOnlyMode(_ value: Bool) {
    menuBarOnlyMode = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.menuBarOnlyMode)
    logCurrentSettings()
  }

  @MainActor
  func setHideDockWhenWindowClosed(_ value: Bool) {
    hideDockWhenWindowClosed = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.hideDockWhenWindowClosed)
    logCurrentSettings()
  }

  @MainActor
  func setNowPlayingFirst(_ value: Bool) {
    nowPlayingFirst = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.nowPlayingFirst)
    logCurrentSettings()
  }

  @MainActor
  func setLockPortraitOrientationiOS(_ value: Bool) {
    lockPortraitOrientationiOS = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.lockPortraitOrientationiOS)
    logCurrentSettings()
  }

  @MainActor
  func setQuickMixSoundFileNames(_ value: [String]) {
    quickMixSoundFileNames = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.quickMixSoundFileNames)
    logCurrentSettings()
    AudioManager.shared.republishWidgetCatalog()
  }

  // MARK: - Starred items (iPad sidebar + CarPlay)

  @MainActor
  func setStarredItems(_ value: [String]) {
    starredItems = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.starredItems)
    // Favorited single sounds take part in lock-screen next/previous.
    AudioManager.shared.updateNextPreviousCommandState()
    AudioManager.shared.republishWidgetCatalog()
  }

  /// Whether the given token (`allSoundsToken`, `quickMixToken`, or a preset
  /// UUID string) is currently starred.
  func isStarred(_ token: String) -> Bool {
    starredItems.contains(token)
  }

  /// Toggle a token's starred membership. Newly starred items append to the end.
  @MainActor
  func toggleStarred(_ token: String) {
    // Mutate a local copy so `starredItems` publishes once, via setStarredItems.
    var items = starredItems
    if let index = items.firstIndex(of: token) {
      items.remove(at: index)
    } else {
      items.append(token)
    }
    setStarredItems(items)
  }

  /// Drop tokens for presets that no longer exist. `allSoundsToken` and
  /// `quickMixToken` are always retained. Single-sound tokens are retained when
  /// `validSoundFileNames` is nil (caller doesn't know the sound list) or when
  /// their file name is still present.
  @MainActor
  func pruneStarredItems(validPresetIDs: Set<String>, validSoundFileNames: Set<String>? = nil) {
    let pruned = starredItems.filter { token in
      switch PlayableItem(token: token) {
      case .allSounds, .quickMix:
        return true
      case .single(let fileName):
        return validSoundFileNames?.contains(fileName) ?? true
      case .preset(let id):
        return validPresetIDs.contains(id.uuidString)
      case nil:
        return false
      }
    }
    if pruned != starredItems {
      setStarredItems(pruned)
    }
  }

  @MainActor
  func setLockScreenBackgroundEnabled(_ value: Bool) {
    lockScreenBackgroundEnabled = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.lockScreenBackgroundEnabled)
    logCurrentSettings()
  }

  @MainActor
  func setDefaultLockScreenArtwork(_ value: AnimatedArtworkRef?) {
    defaultLockScreenArtwork = value
    if let value, let data = try? JSONEncoder().encode(value) {
      UserDefaults.shared.set(data, forKey: UserDefaultsKeys.defaultLockScreenArtwork)
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.defaultLockScreenArtwork)
    }
    logCurrentSettings()
  }

  @MainActor
  func setBackgroundBlurRadius(_ value: Double) {
    backgroundBlurRadius = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.backgroundBlurRadius)
    logCurrentSettings()
  }

  @MainActor
  func setLanguage(_ newLanguage: Language) {
    guard newLanguage.code != language.code else {
      Logger.settings.debug("Language not changed (already set to \(self.language.code))")
      return
    }

    Logger.settings.debug(
      "GlobalSettings: Changing language from \(self.language.code) to \(newLanguage.code)")
    language = newLanguage
    UserDefaults.shared.setValue(newLanguage.code, forKey: UserDefaultsKeys.language)

    needsRestartForLanguageChange = true
    Language.applyLanguage(newLanguage)
    logCurrentSettings()
  }

}
