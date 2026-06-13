//
//  GlobalSettings.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import AVFoundation
import Foundation
import SwiftUI
import os

enum IconSize: String, CaseIterable {
  case small = "Small"
  case medium = "Medium"
  case large = "Large"

  var label: String { rawValue }
}

extension UserDefaults {
  /// Shared UserDefaults instance for app group
  /// Falls back to standard UserDefaults if app group is not available
  static var shared: UserDefaults {
    AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
  }

}

enum UserDefaultsKeys {
  static let volume = "globalVolume"
  static let accentColor = "customAccentColor"
  /// Legacy autoplay key (pre-2.0). Migrated to `autoPlayOnLaunchMac`
  static let autoPlayOnLaunch = "autoPlayOnLaunch"
  static let autoPlayOnLaunchMac = "autoPlayOnLaunchMac"
  static let enableSpatialAudio = "enableSpatialAudio"
  static let language = "languagePreference"
  static let mixWithOthers = "mixWithOthers"
  static let volumeWithOtherAudio = "volumeWithOtherAudio"
  static let showSoundNames = "showSoundNames"
  static let iconSize = "iconSize"
  static let soloModeSoundFileName = "soloModeSoundFileName"
  static let showingListView = "showingListView"
  static let showProgressBorder = "showProgressBorder"
  static let lockPortraitOrientationiOS = "lockPortraitOrientationiOS"
  static let quickMixSoundFileNames = "quickMixSoundFileNames"
  static let lockScreenBackgroundEnabled = "lockScreenBackgroundEnabled"
  static let defaultLockScreenArtwork = "defaultLockScreenArtwork"
  static let starredItems = "starredItems"
  static let backgroundBlurRadius = "backgroundBlurRadius"
  static let showDockBadgeWhenPaused = "showDockBadgeWhenPaused"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let menuBarOnlyMode = "menuBarOnlyMode"
  static let hideDockWhenWindowClosed = "hideDockWhenWindowClosed"
}

/// Blur (in points) applied to a preset's background artwork behind the mixer
/// when "Blur Background" is on. Blur is now on/off: any radius > 0 means on,
/// at this value. Presets may override this with their own `backgroundBlurRadius`.
let defaultBackgroundBlurRadius: Double = 7.5

@Observable
class GlobalSettings {
  var needsRestartForLanguageChange = false
  static let shared = GlobalSettings()

  /// Tokens for the non-preset starrable items. Presets use their UUID string.
  static let allSoundsToken = "allSounds"
  static let quickMixToken = "quickMix"

  /// Prefix for solo-sound tokens. A soloed sound is starred as
  /// `"solo:<fileName>"`, using the sound's stable `fileName` as its identity.
  static let soloTokenPrefix = "solo:"

  /// The starred token for soloing the given sound file.
  static func soloToken(forFileName fileName: String) -> String {
    soloTokenPrefix + fileName
  }

  /// The sound file name encoded in a solo token, or nil if it isn't one.
  static func soloFileName(fromToken token: String) -> String? {
    token.hasPrefix(soloTokenPrefix) ? String(token.dropFirst(soloTokenPrefix.count)) : nil
  }

  var volume: Double
  var customAccentColor: Color?
  var autoPlayOnLaunch: Bool
  var showSoundNames: Bool
  var iconSize: IconSize
  var language: Language
  var showingListView: Bool
  var showProgressBorder: Bool
  var lockPortraitOrientationiOS: Bool
  var quickMixSoundFileNames: [String]
  /// Ordered list of starred items shown in the iPad sidebar and CarPlay.
  /// Tokens: `allSoundsToken`, `quickMixToken`, a preset's UUID string, or a
  /// solo-sound token (`soloToken(forFileName:)`).
  /// Order = display order; membership = starred.
  var starredItems: [String]
  var availableLanguages: [Language] = []
  var lockScreenBackgroundEnabled: Bool
  /// App-wide default lock screen animation. Used on the lock screen for any
  /// preset that doesn't set its own `animatedArtwork`.
  var defaultLockScreenArtwork: AnimatedArtworkRef?
  /// App-wide default blur (in points) for preset background artwork. A preset's
  /// own `backgroundBlurRadius` overrides this when set.
  var backgroundBlurRadius: Double
  /// macOS only: badge the Dock icon with a pause glyph while the app is
  /// silent. On by default.
  var showDockBadgeWhenPaused: Bool
  /// macOS only: show Blankie's icon in the menu bar. On by default.
  var showMenuBarIcon: Bool
  /// macOS only: hide the Dock icon now (menu-bar-only mode). Off by default.
  var menuBarOnlyMode: Bool
  /// macOS only: hide the Dock icon while the main window is closed. Off by
  /// default.
  var hideDockWhenWindowClosed: Bool

  // Platform-specific settings
  /// Availability gate for the experimental spatial feature: shows the
  /// Spatial Mix entry on presets. Sessions themselves are started in-sheet.
  var enableSpatialAudio: Bool = false
  var mixWithOthers: Bool = false
  var volumeWithOtherAudio: Double = 0.5  // 0.0 = silent, 1.0 = full volume

  var volumeDebounceTimer: Timer?

  private init() {
    // Initialize required properties first
    volume = 1.0
    customAccentColor = nil
    autoPlayOnLaunch = false
    showSoundNames = true
    iconSize = .medium
    language = .system
    showingListView = false
    showProgressBorder = false
    lockPortraitOrientationiOS = false
    quickMixSoundFileNames = [
      "rain", "waves", "fireplace", "white-noise",
      "wind", "stream", "birds", "coffee-shop",
    ]
    starredItems = []
    availableLanguages = []
    lockScreenBackgroundEnabled = true
    backgroundBlurRadius = defaultBackgroundBlurRadius
    showDockBadgeWhenPaused = true
    showMenuBarIcon = true
    menuBarOnlyMode = false
    hideDockWhenWindowClosed = false

    // Then load actual values from UserDefaults
    loadBasicSettings()
    loadPlatformSettings()
    loadLanguageSettings()
    migrateLegacySettings()

    // After initialization, log current settings
    logCurrentSettings()
  }

  @MainActor
  func setVolume(_ newVolume: Double) {
    volume = validateVolume(newVolume)
    AudioEngineManager.shared.applyGlobalVolumeSettings()
    debouncedSaveVolume(volume)
    logCurrentSettings()
  }
}

// MARK: - Volume

extension GlobalSettings {
  func validateVolume(_ volume: Double) -> Double {
    min(max(volume, 0.0), 1.0)
  }

  func debouncedSaveVolume(_ newVolume: Double) {
    volumeDebounceTimer?.invalidate()
    volumeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
      [weak self] _ in
      self?.saveVolume(newVolume)
    }
  }

  private func saveVolume(_ newVolume: Double) {
    let validVolume = validateVolume(newVolume)
    UserDefaults.shared.set(validVolume, forKey: UserDefaultsKeys.volume)
    Logger.settings.debug("GlobalSettings: Saved volume: \(validVolume)")
  }
}

// MARK: - Solo Mode

extension GlobalSettings {
  @MainActor
  func saveSoloModeSound(fileName: String?) {
    if let fileName = fileName {
      UserDefaults.shared.set(fileName, forKey: UserDefaultsKeys.soloModeSoundFileName)
      Logger.settings.debug("GlobalSettings: Saved solo mode sound: \(fileName)")
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.soloModeSoundFileName)
      Logger.settings.debug("GlobalSettings: Cleared solo mode sound")
    }
  }

  func getSavedSoloModeFileName() -> String? {
    return UserDefaults.shared.string(forKey: UserDefaultsKeys.soloModeSoundFileName)
  }
}

// MARK: - Platform Settings

extension GlobalSettings {
  @MainActor
  func setEnableSpatialAudio(_ value: Bool) {
    enableSpatialAudio = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.enableSpatialAudio)
    // Availability gate only; turning it off ends any live session.
    if !value, SpatialSessionManager.shared.isActive {
      SpatialSessionManager.shared.setMode(.off)
    }
    logCurrentSettings()
  }

  #if os(iOS) || os(visionOS)
    @MainActor
    func setMixWithOthers(_ value: Bool) {
      mixWithOthers = value
      UserDefaults.shared.set(value, forKey: UserDefaultsKeys.mixWithOthers)

      // Reset volume to 100% when disabling mix with others
      if !value && volumeWithOtherAudio < 1.0 {
        volumeWithOtherAudio = 1.0
        UserDefaults.shared.set(
          volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
      }

      // Update audio session configuration
      updateAudioSession()

      // Apply the new volume settings to currently playing sounds
      if AudioManager.shared.isGloballyPlaying {
        AudioManager.shared.applyVolumeSettings()
      }

      // Global mix gain lives on the engine's main mixer.
      AudioEngineManager.shared.applyGlobalVolumeSettings()

      logCurrentSettings()
    }
  #endif

  @MainActor
  func setVolumeWithOtherAudio(_ level: Double) {
    volumeWithOtherAudio = max(0.0, min(1.0, level))  // Clamp between 0.0 and 1.0
    UserDefaults.shared.set(volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
    // Apply the new volume level to currently playing sounds
    if AudioManager.shared.isGloballyPlaying {
      AudioManager.shared.applyVolumeSettings()
    }
    AudioEngineManager.shared.applyGlobalVolumeSettings()
    logCurrentSettings()
  }
}

// MARK: - Audio Session

#if os(iOS) || os(visionOS)
  extension GlobalSettings {
    func updateAudioSession() {
      do {
        let wasPlaying = AudioManager.shared.isGloballyPlaying

        // Configure the session based on mixWithOthers setting
        if mixWithOthers {
          // Allow mixing with other apps - we handle volume manually
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          Logger.settings.debug("GlobalSettings: Setting Mix mode with manual volume control")

          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: options
          )
        } else {
          // Exclusive playback mode - no mixing
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // No options means exclusive playback
          )
        }

        // Always activate if we're currently playing to ensure we take over
        if wasPlaying {
          try AVAudioSession.sharedInstance().setActive(true)

          // Note: We don't call playSelected() here to preserve playback positions
          // The audio players will automatically continue from their current positions

          // Update Now Playing info
          AudioManager.shared.updateNowPlayingState()
        }

        Logger.settings.debug(
          "GlobalSettings: Updated audio session with mixWithOthers: \(self.mixWithOthers), volumeWithOtherAudio: \(self.volumeWithOtherAudio), activated: \(wasPlaying)"
        )
      } catch {
        Logger.settings.error(
          "GlobalSettings: Failed to update audio session: \(error, privacy: .public)")
      }
    }
  }
#endif

// MARK: - Logging

extension GlobalSettings {
  func logCurrentSettings() {
    Logger.settings.debug(
      """
      GlobalSettings: Current State
        - Volume: \(self.volume)
        - Custom Accent Color: \(self.customAccentColor?.toString ?? "System")
        - Autoplay on Open: \(self.autoPlayOnLaunch)
        - Enable Spatial Audio: \(self.enableSpatialAudio)
        - Mix With Others: \(self.mixWithOthers)
        - Volume With Other Audio: \(self.volumeWithOtherAudio)
        - Lock Screen Background Enabled: \(self.lockScreenBackgroundEnabled)
        - Language: \(self.language.code)
        - Available Languages: \(self.availableLanguages.map { $0.code }.joined(separator: ", "))
      """)
  }
}
