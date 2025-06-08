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

enum UserDefaultsKeys {
  static let volume = "globalVolume"
  static let appearance = "appearanceMode"
  static let accentColor = "customAccentColor"
  static let autoPlayOnLaunch = "autoPlayOnLaunch"
  static let hideInactiveSounds = "hideInactiveSounds"
  static let enableHaptics = "enableHaptics"
  static let enableSpatialAudio = "enableSpatialAudio"
  static let language = "languagePreference"
  static let mixWithOthers = "mixWithOthers"
  static let lowerVolumeWithOtherAudio = "lowerVolumeWithOtherAudio"
  static let volumeWithOtherAudio = "volumeWithOtherAudio"
  static let showSoundNames = "showSoundNames"
  static let iconSize = "iconSize"
  static let soloModeSoundFileName = "soloModeSoundFileName"
  static let showingListView = "showingListView"
  static let showProgressBorder = "showProgressBorder"
  static let hideInactiveSoundSliders = "hideInactiveSoundSliders"
  static let lockPortraitOrientationiOS = "lockPortraitOrientationiOS"
}

class GlobalSettings: ObservableObject {
  @Published var needsRestartForLanguageChange = false
  static let shared = GlobalSettings()

  @Published var volume: Double
  @Published var appearance: AppearanceMode
  @Published var customAccentColor: Color?
  @Published var autoPlayOnLaunch: Bool
  @Published var hideInactiveSounds: Bool
  @Published var showSoundNames: Bool
  @Published var iconSize: IconSize
  @Published var language: Language
  @Published var showingListView: Bool
  @Published var showProgressBorder: Bool
  @Published var hideInactiveSoundSliders: Bool
  @Published var lockPortraitOrientationiOS: Bool
  @Published var availableLanguages: [Language] = []

  // Platform-specific settings
  @Published var enableHaptics: Bool = true
  @Published var enableSpatialAudio: Bool = false
  @Published var mixWithOthers: Bool = false
  @Published var lowerVolumeWithOtherAudio: Bool = false
  @Published var volumeWithOtherAudio: Double = 0.5  // 0.0 = silent, 1.0 = full volume

  var observers = Set<AnyCancellable>()
  var volumeDebounceTimer: Timer?

  private init() {
    // Initialize required properties first
    volume = 1.0
    appearance = .system
    customAccentColor = nil
    autoPlayOnLaunch = false
    hideInactiveSounds = false
    showSoundNames = true
    iconSize = .medium
    language = .system
    showingListView = false
    showProgressBorder = true
    hideInactiveSoundSliders = false
    lockPortraitOrientationiOS = false
    availableLanguages = []

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
