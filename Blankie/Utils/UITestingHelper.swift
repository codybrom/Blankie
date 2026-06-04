//
//  UITestingHelper.swift
//  Blankie
//
//  Created by Cody Bromley on 5/27/25.
//

import Foundation
import os

/// Helper class for UI testing setup and teardown
enum UITestingHelper {

  /// Check if we're running in UI testing mode with reset flag
  static func shouldResetForUITesting() -> Bool {
    return ProcessInfo.processInfo.arguments.contains("-UITestingResetDefaults")
  }

  /// Reset all UserDefaults to provide a clean state for UI testing
  static func resetAllDefaults() {
    guard shouldResetForUITesting() else { return }

    Logger.app.debug("UITestingHelper: Resetting all UserDefaults for UI testing")

    resetAppBundle()
    resetPresetDefaults()
    resetWindowFrameData()
    resetGlobalSettings()
    configureUITestingDefaults()
    configureAppearanceMode()
    setConsistentWindowSize()
    resetSoundDefaults()

    UserDefaults.standard.synchronize()
    verifyWindowFrame()

    Logger.app.debug("UITestingHelper: UserDefaults reset complete")
  }

  private static func resetAppBundle() {
    if let bundleId = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
      UserDefaults.standard.synchronize()
    }
  }

  private static func resetPresetDefaults() {
    UserDefaults.standard.removeObject(forKey: "presets")
    UserDefaults.standard.removeObject(forKey: "currentPresetID")
  }

  private static func resetWindowFrameData() {
    UserDefaults.standard.removeObject(forKey: "LastWindowFrame")
    UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")
    UserDefaults.standard.removeObject(forKey: "HasSavedWindowPosition")
  }

  private static func resetGlobalSettings() {
    UserDefaults.standard.removeObject(forKey: "globalVolume")
    UserDefaults.standard.removeObject(forKey: "customAccentColor")
    UserDefaults.standard.removeObject(forKey: "colorScheme")
  }

  private static func configureUITestingDefaults() {
    UserDefaults.standard.set(false, forKey: "alwaysStartPaused")

    if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") {
      UserDefaults.standard.set(true, forKey: "forceStartPlayback")
    }
  }

  private static func configureAppearanceMode() {
    if ProcessInfo.processInfo.arguments.contains("-ForceDarkMode") {
      UserDefaults.standard.set("dark", forKey: "appearanceMode")
    } else {
      UserDefaults.standard.set("light", forKey: "appearanceMode")
    }
  }

  private static func setConsistentWindowSize() {
    let windowFrameDict: [String: Double] = [
      "x": 485.0,
      "y": 277.0,
      "width": 950.0,
      "height": 540.0,
    ]
    UserDefaults.standard.set(windowFrameDict, forKey: "LastWindowFrame")
    UserDefaults.standard.set(true, forKey: "HasSavedWindowPosition")
  }

  private static func resetSoundDefaults() {
    let soundNames = [
      "rain", "storm", "wind", "waves", "stream", "birds", "summer-night",
      "train", "boat", "city", "coffee-shop", "fireplace", "pink-noise", "white-noise",
    ]

    if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") {
      configureScreenshotSounds(soundNames: soundNames)
    } else {
      clearAllSounds(soundNames: soundNames)
    }
  }

  private static func configureScreenshotSounds(soundNames: [String]) {
    for soundName in soundNames {
      UserDefaults.standard.removeObject(forKey: "\(soundName)_volume")
      UserDefaults.standard.set(false, forKey: "\(soundName)_isSelected")
    }

    let screenshotSounds: [(name: String, volume: Double)] = [
      ("rain", 0.8),
      ("storm", 0.6),
      ("wind", 0.9),
      ("waves", 0.4),
      ("boat", 0.7),
    ]

    for (name, volume) in screenshotSounds {
      UserDefaults.standard.set(true, forKey: "\(name)_isSelected")
      UserDefaults.standard.set(volume, forKey: "\(name)_volume")
    }
  }

  private static func clearAllSounds(soundNames: [String]) {
    for soundName in soundNames {
      UserDefaults.standard.removeObject(forKey: "\(soundName)_volume")
      UserDefaults.standard.removeObject(forKey: "\(soundName)_isSelected")
    }
  }

  private static func verifyWindowFrame() {
    if let savedFrame = UserDefaults.standard.dictionary(forKey: "LastWindowFrame") {
      Logger.app.debug("UITestingHelper: Window frame set to: \(savedFrame)")
    }
  }
}
