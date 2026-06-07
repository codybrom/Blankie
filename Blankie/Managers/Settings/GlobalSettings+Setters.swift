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
  func setAppearance(_ newAppearance: AppearanceMode) {
    appearance = newAppearance
    UserDefaults.shared.setValue(newAppearance.rawValue, forKey: UserDefaultsKeys.appearance)
    updateAppAppearance()
    logCurrentSettings()
  }

  @MainActor
  func setAccentColor(_ newColor: Color?) {
    customAccentColor = newColor
    if let color = newColor {
      UserDefaults.shared.set(color.toString, forKey: UserDefaultsKeys.accentColor)
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.accentColor)
    }
    logCurrentSettings()
  }

  @MainActor
  func setAutoPlayOnLaunch(_ value: Bool) {
    autoPlayOnLaunch = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.autoPlayOnLaunch)
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
  }

  // MARK: - Starred items (iPad sidebar + CarPlay)

  @MainActor
  func setStarredItems(_ value: [String]) {
    starredItems = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.starredItems)
    // A favorited solo sound participates in lock-screen next/previous, so the
    // command availability depends on the favorites list — refresh it here.
    AudioManager.shared.updateNextPreviousCommandState()
  }

  /// Whether the given token (`allSoundsToken`, `quickMixToken`, or a preset
  /// UUID string) is currently starred.
  func isStarred(_ token: String) -> Bool {
    starredItems.contains(token)
  }

  /// Toggle a token's starred membership. Newly starred items append to the end.
  @MainActor
  func toggleStarred(_ token: String) {
    // Mutate a local copy so `starredItems` publishes once (via setStarredItems),
    // not twice — a double publish made the CarPlay observer rebuild its template
    // twice, the first time reading the pre-mutation value.
    var items = starredItems
    if let index = items.firstIndex(of: token) {
      items.remove(at: index)
    } else {
      items.append(token)
    }
    setStarredItems(items)
  }

  /// Drop tokens for presets that no longer exist. `allSoundsToken` and
  /// `quickMixToken` are always retained. Solo-sound tokens are retained when
  /// `validSoundFileNames` is nil (caller doesn't know the sound list) or when
  /// their file name is still present.
  @MainActor
  func pruneStarredItems(validPresetIDs: Set<String>, validSoundFileNames: Set<String>? = nil) {
    let pruned = starredItems.filter { token in
      if let fileName = GlobalSettings.soloFileName(fromToken: token) {
        return validSoundFileNames?.contains(fileName) ?? true
      }
      return token == GlobalSettings.allSoundsToken
        || token == GlobalSettings.quickMixToken
        || validPresetIDs.contains(token)
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

  private func updateAppAppearance() {
    #if os(macOS)
      DispatchQueue.main.async {
        switch self.appearance {
        case .system:
          NSApp.appearance = nil
        case .light:
          NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
          NSApp.appearance = NSAppearance(named: .darkAqua)
        }
      }
    #endif
  }
}
