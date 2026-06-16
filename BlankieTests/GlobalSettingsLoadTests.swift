//
//  GlobalSettingsLoadTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  loadBasicSettings encodes explicit bug-fix invariants: a saved 0 volume must
//  not be reset to full, and a legacy blur radius must normalize to the single
//  on/off value while a saved 0 ("off") stays 0. A regression here silently
//  resets a user's saved setting on the next launch.
//
//  Serialized + restores both the touched defaults and the singleton's in-memory
//  values, since it drives the GlobalSettings.shared singleton.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) final class GlobalSettingsLoadTests {
  private let settings = GlobalSettings.shared
  private let snapshot = DefaultsSnapshot([
    UserDefaultsKeys.volume, UserDefaultsKeys.backgroundBlurRadius,
  ])
  private let originalVolume: Double
  private let originalBlur: Double

  init() {
    originalVolume = settings.volume
    originalBlur = settings.backgroundBlurRadius
    snapshot.clear()
  }
  deinit {
    settings.volume = originalVolume
    settings.backgroundBlurRadius = originalBlur
    snapshot.restore()
  }

  /// A deliberately-saved 0 volume must NOT be reset to 1.0 on load (object(forKey:)
  /// distinguishes "saved zero" from "never saved").
  @Test func loadPreservesSavedZeroVolume() {
    UserDefaults.shared.set(0.0, forKey: UserDefaultsKeys.volume)
    settings.loadBasicSettings()
    #expect(isClose(settings.volume, 0.0))
  }

  /// No saved volume → default to full.
  @Test func loadDefaultsVolumeToFullWhenUnset() {
    UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.volume)
    settings.loadBasicSettings()
    #expect(isClose(settings.volume, 1.0))
  }

  /// A legacy blur radius (> 0, e.g. the old "High" 15) normalizes to the single
  /// on value AND rewrites the stored value to match.
  @Test func loadNormalizesLegacyBlurAndRewrites() {
    UserDefaults.shared.set(15.0, forKey: UserDefaultsKeys.backgroundBlurRadius)
    settings.loadBasicSettings()

    #expect(isClose(settings.backgroundBlurRadius, defaultBackgroundBlurRadius))
    let stored = UserDefaults.shared.object(forKey: UserDefaultsKeys.backgroundBlurRadius) as? Double
    #expect(stored != nil && isClose(stored ?? -1, defaultBackgroundBlurRadius))
  }

  /// A saved 0 ("blur off") stays 0 — not mistaken for "unset" and bumped to the
  /// default.
  @Test func loadKeepsBlurOff() {
    UserDefaults.shared.set(0.0, forKey: UserDefaultsKeys.backgroundBlurRadius)
    settings.loadBasicSettings()
    #expect(isClose(settings.backgroundBlurRadius, 0))
  }
}
