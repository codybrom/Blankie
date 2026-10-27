//
//  GlobalSettingsLoadTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  loadBasicSettings keeps saved zeros (volume, blur off) and normalizes legacy blur radii.
//  Serialized: restores the touched defaults and GlobalSettings.shared values.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) final class GlobalSettingsLoadTests {
  private let settings = GlobalSettings.shared
  private let snapshot = DefaultsSnapshot([
    UserDefaultsKeys.volume, UserDefaultsKeys.backgroundBlurRadius,
    UserDefaultsKeys.showPlaybackAsContinuous, UserDefaultsKeys.nowPlayingFirst,
  ])
  private let originalVolume: Double
  private let originalBlur: Double
  private let originalContinuous: Bool
  private let originalNowPlayingFirst: Bool

  init() {
    originalVolume = settings.volume
    originalBlur = settings.backgroundBlurRadius
    originalContinuous = settings.showPlaybackAsContinuous
    originalNowPlayingFirst = settings.nowPlayingFirst
    snapshot.clear()
  }
  isolated deinit {
    settings.volume = originalVolume
    settings.backgroundBlurRadius = originalBlur
    settings.showPlaybackAsContinuous = originalContinuous
    settings.nowPlayingFirst = originalNowPlayingFirst
    snapshot.restore()
  }

  /// `object(forKey:)` tells a saved zero from a missing value.
  @Test func loadPreservesSavedZeroVolume() {
    UserDefaults.shared.set(0.0, forKey: UserDefaultsKeys.volume)
    settings.loadBasicSettings()
    #expect(isClose(settings.volume, 0.0))
  }

  @Test func loadDefaultsVolumeToFullWhenUnset() {
    UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.volume)
    settings.loadBasicSettings()
    #expect(isClose(settings.volume, 1.0))
  }

  /// Legacy radii (such as the old "High" 15) normalize to the single on value.
  @Test func loadNormalizesLegacyBlurAndRewrites() {
    UserDefaults.shared.set(15.0, forKey: UserDefaultsKeys.backgroundBlurRadius)
    settings.loadBasicSettings()

    #expect(isClose(settings.backgroundBlurRadius, defaultBackgroundBlurRadius))
    let stored =
      UserDefaults.shared.object(forKey: UserDefaultsKeys.backgroundBlurRadius) as? Double
    #expect(stored != nil && isClose(stored ?? -1, defaultBackgroundBlurRadius))
  }

  /// A saved 0 means blur off, not unset.
  @Test func loadKeepsBlurOff() {
    UserDefaults.shared.set(0.0, forKey: UserDefaultsKeys.backgroundBlurRadius)
    settings.loadBasicSettings()
    #expect(isClose(settings.backgroundBlurRadius, 0))
  }
  @Test func continuousPlaybackDefaultsOnAndPreservesSavedOptOut() {
    UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.showPlaybackAsContinuous)
    settings.loadBasicSettings()
    #expect(settings.showPlaybackAsContinuous)
    settings.setShowPlaybackAsContinuous(false)
    #expect(
      UserDefaults.shared.object(forKey: UserDefaultsKeys.showPlaybackAsContinuous) as? Bool
        == false)
    settings.showPlaybackAsContinuous = true
    settings.loadBasicSettings()
    #expect(!settings.showPlaybackAsContinuous)
    #expect(settings.showsPlaybackProgress(timerActive: false))
    settings.showPlaybackAsContinuous = true
    #expect(settings.showsPlaybackProgress(timerActive: true))
    if #available(iOS 27, macOS 27, visionOS 27, *) {
      #expect(!settings.showsPlaybackProgress(timerActive: false))
    } else {
      #expect(settings.showsPlaybackProgress(timerActive: false))
    }
  }

  @Test func nowPlayingFirstDefaultsOnAndPreservesSavedOptOut() {
    UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.nowPlayingFirst)
    settings.loadBasicSettings()
    #expect(settings.nowPlayingFirst)
    settings.setNowPlayingFirst(false)
    settings.nowPlayingFirst = true
    settings.loadBasicSettings()
    #expect(!settings.nowPlayingFirst)
  }

}
