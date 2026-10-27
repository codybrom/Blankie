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
  /// The app group's UserDefaults, or `.standard` when the group is unavailable.
  static var shared: UserDefaults {
    AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
  }

}

enum UserDefaultsKeys {
  static let volume = "globalVolume"
  static let accentColor = "customAccentColor"
  /// Legacy autoplay key (pre-2.0), migrated to `autoPlayOnLaunchMac`.
  static let autoPlayOnLaunch = "autoPlayOnLaunch"
  static let autoPlayOnLaunchMac = "autoPlayOnLaunchMac"
  static let enableSpatialAudio = "enableSpatialAudio"
  static let language = "languagePreference"
  static let mixWithOthers = "mixWithOthers"
  static let volumeWithOtherAudio = "volumeWithOtherAudio"
  static let showSoundNames = "showSoundNames"
  static let iconSize = "iconSize"
  // Stored key. Keep the "solo" spelling, or every saved single sound is lost.
  static let singleSoundFileName = "soloModeSoundFileName"
  static let showingListView = "showingListView"
  static let showProgressBorder = "showProgressBorder"
  static let showPlaybackAsContinuous = "showPlaybackAsContinuous"
  static let lockPortraitOrientationiOS = "lockPortraitOrientationiOS"
  static let nowPlayingFirst = "nowPlayingFirst"
  static let quickMixSoundFileNames = "quickMixSoundFileNames"
  static let lockScreenBackgroundEnabled = "lockScreenBackgroundEnabled"
  static let defaultLockScreenArtwork = "defaultLockScreenArtwork"
  static let starredItems = "starredItems"
  static let backgroundBlurRadius = "backgroundBlurRadius"
  static let showDockBadgeWhenPaused = "showDockBadgeWhenPaused"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let menuBarOnlyMode = "menuBarOnlyMode"
  static let hideDockWhenWindowClosed = "hideDockWhenWindowClosed"
  static let librarySoundsExpanded = "librarySoundsExpanded"
  static let libraryPresetsExpanded = "libraryPresetsExpanded"
}

/// Blur (in points) behind the mixer when "Blur Background" is on. Blur is
/// on/off and app-wide: any saved radius above 0 means on, at this value.
let defaultBackgroundBlurRadius: Double = 7.5

@Observable
class GlobalSettings {
  var needsRestartForLanguageChange = false
  static let shared = GlobalSettings()

  /// Tokens for the non-preset starrable items. Presets use their UUID string.
  /// These forward to `PlayableItem`, the single codec for the token grammar.
  static let allSoundsToken = PlayableItem.allSounds.token
  static let quickMixToken = PlayableItem.quickMix.token

  /// Prefix for single-sound tokens. A single sound is starred as
  /// `"solo:<fileName>"`, using the sound's stable `fileName` as its identity.
  static let singleTokenPrefix = PlayableItem.singleTokenPrefix

  /// The starred token for playing the given sound file on its own.
  static func singleToken(forFileName fileName: String) -> String {
    PlayableItem.single(fileName: fileName).token
  }

  /// The sound file name encoded in a single sound token, or nil if it isn't one.
  static func singleFileName(fromToken token: String) -> String? {
    if case .single(let fileName) = PlayableItem(token: token) { return fileName }
    return nil
  }

  var volume: Double
  var customAccentColor: Color?
  var autoPlayOnLaunch: Bool
  var showSoundNames: Bool
  var iconSize: IconSize
  var language: Language
  var showingListView: Bool
  var showProgressBorder: Bool
  var showPlaybackAsContinuous: Bool

  /// Continuous metadata is available only through the OS 27 backend.
  var usesContinuousPlayback: Bool {
    if #available(iOS 27, macOS 27, visionOS 27, *) {
      return showPlaybackAsContinuous
    }
    return false
  }

  func showsPlaybackProgress(timerActive: Bool) -> Bool {
    !usesContinuousPlayback || timerActive
  }

  var lockPortraitOrientationiOS: Bool
  /// iPhone: choosing a preset or sound opens Now Playing, with the mixer one
  /// tap away (on), or opens the mixer first (off).
  var nowPlayingFirst: Bool
  var quickMixSoundFileNames: [String]
  /// Starred items in display order, shown in the iPad sidebar and CarPlay.
  /// Tokens: `allSoundsToken`, `quickMixToken`, a preset's UUID string, or a
  /// single-sound token (`singleToken(forFileName:)`).
  var starredItems: [String]
  var availableLanguages: [Language] = []
  var lockScreenBackgroundEnabled: Bool
  /// App-wide default lock screen animation. Used on the lock screen for any
  /// preset that doesn't set its own `animatedArtwork`.
  var defaultLockScreenArtwork: AnimatedArtworkRef?
  /// App-wide blur (in points) for preset background artwork, where 0 means off.
  var backgroundBlurRadius: Double
  /// macOS only: badge the Dock icon with a pause glyph while the app is silent.
  var showDockBadgeWhenPaused: Bool
  /// macOS only: show Blankie's icon in the menu bar.
  var showMenuBarIcon: Bool
  /// macOS only: hide the Dock icon now (menu-bar-only mode).
  var menuBarOnlyMode: Bool
  /// macOS only: hide the Dock icon while the main window is closed.
  var hideDockWhenWindowClosed: Bool
  /// Whether the Library's Sounds and Presets sections are expanded.
  var librarySoundsExpanded: Bool
  var libraryPresetsExpanded: Bool

  /// Availability gate for the experimental spatial feature: shows the
  /// Spatial Mix entry on presets. Sessions themselves are started in-sheet.
  var enableSpatialAudio: Bool = false
  var mixWithOthers: Bool = false
  var volumeWithOtherAudio: Double = 0.5  // 0.0 = silent, 1.0 = full volume

  var volumeDebounceTimer: Timer?

  private init() {
    volume = 1.0
    customAccentColor = nil
    autoPlayOnLaunch = false
    showSoundNames = true
    iconSize = .medium
    language = .system
    showingListView = false
    showProgressBorder = true
    showPlaybackAsContinuous = true
    lockPortraitOrientationiOS = false
    nowPlayingFirst = true
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
    librarySoundsExpanded = true
    libraryPresetsExpanded = true

    loadBasicSettings()
    loadPlatformSettings()
    loadLanguageSettings()
    migrateLegacySettings()

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
      MainActor.assumeIsolated { self?.saveVolume(newVolume) }
    }
  }

  /// Saves a pending debounced volume now (the app is quitting or suspending).
  func flushPendingVolumeSave() {
    volumeDebounceTimer?.fire()
  }

  private func saveVolume(_ newVolume: Double) {
    let validVolume = validateVolume(newVolume)
    UserDefaults.shared.set(validVolume, forKey: UserDefaultsKeys.volume)
    Logger.settings.debug("GlobalSettings: Saved volume: \(validVolume)")
  }
}

// MARK: - Single Sound

extension GlobalSettings {
  @MainActor
  func saveSingleSound(fileName: String?) {
    if let fileName = fileName {
      UserDefaults.shared.set(fileName, forKey: UserDefaultsKeys.singleSoundFileName)
      Logger.settings.debug("GlobalSettings: Saved single sound: \(fileName)")
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.singleSoundFileName)
      Logger.settings.debug("GlobalSettings: Cleared single sound")
    }
  }

  func getSavedSingleSoundFileName() -> String? {
    return UserDefaults.shared.string(forKey: UserDefaultsKeys.singleSoundFileName)
  }
}

// MARK: - Platform Settings

extension GlobalSettings {
  @MainActor
  func setEnableSpatialAudio(_ value: Bool) {
    enableSpatialAudio = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.enableSpatialAudio)
    // Availability gate only. Turning it off ends any live session.
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

      if !value && volumeWithOtherAudio < 1.0 {
        volumeWithOtherAudio = 1.0
        UserDefaults.shared.set(
          volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
      }

      updateAudioSession()

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
    volumeWithOtherAudio = max(0.0, min(1.0, level))
    UserDefaults.shared.set(volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
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

        if mixWithOthers {
          // Mixing with other apps. Blankie applies its own volume.
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          Logger.settings.debug("GlobalSettings: Setting Mix mode with manual volume control")

          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: options
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // No options means exclusive playback
          )
        }

        // Reactivate while playing so the new category takes effect.
        if wasPlaying {
          try AVAudioSession.sharedInstance().setActive(true)

          // No playSelected() here, so players keep their current positions.
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
