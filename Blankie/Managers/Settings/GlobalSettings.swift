//
//  GlobalSettings.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

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
  static let appearance = "appearanceMode"
  static let accentColor = "customAccentColor"
  static let autoPlayOnLaunch = "autoPlayOnLaunch"
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
  static let starredItems = "starredItems"
  static let backgroundBlurRadius = "backgroundBlurRadius"
}

/// Blur (in points) applied to a preset's background artwork behind the mixer
/// when "Blur Background" is on. Blur is now on/off: any radius > 0 means on,
/// at this value. Presets may override this with their own `backgroundBlurRadius`.
let defaultBackgroundBlurRadius: Double = 7.5

class GlobalSettings: ObservableObject {
  @Published var needsRestartForLanguageChange = false
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

  @Published var volume: Double
  @Published var appearance: AppearanceMode
  @Published var customAccentColor: Color?
  @Published var autoPlayOnLaunch: Bool
  @Published var showSoundNames: Bool
  @Published var iconSize: IconSize
  @Published var language: Language
  @Published var showingListView: Bool
  @Published var showProgressBorder: Bool
  @Published var lockPortraitOrientationiOS: Bool
  @Published var quickMixSoundFileNames: [String]
  /// Ordered list of starred items shown in the iPad sidebar and CarPlay.
  /// Tokens: `allSoundsToken`, `quickMixToken`, a preset's UUID string, or a
  /// solo-sound token (`soloToken(forFileName:)`).
  /// Order = display order; membership = starred.
  @Published var starredItems: [String]
  @Published var availableLanguages: [Language] = []
  @Published var lockScreenBackgroundEnabled: Bool
  /// App-wide default blur (in points) for preset background artwork. A preset's
  /// own `backgroundBlurRadius` overrides this when set.
  @Published var backgroundBlurRadius: Double

  // Platform-specific settings
  @Published var enableSpatialAudio: Bool = false
  @Published var mixWithOthers: Bool = false
  @Published var volumeWithOtherAudio: Double = 0.5  // 0.0 = silent, 1.0 = full volume

  var observers = Set<AnyCancellable>()
  var volumeDebounceTimer: Timer?

  private init() {
    // Initialize required properties first
    volume = 1.0
    appearance = .system
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
    debouncedSaveVolume(volume)
    logCurrentSettings()
  }
}
