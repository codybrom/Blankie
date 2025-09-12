//
//  UserDefaults+AppGroup.swift
//  Blankie
//
//  Created by Cody Bromley on 7/12/25.
//

import Foundation

extension UserDefaults {
  /// Shared UserDefaults instance for app group
  /// Falls back to standard UserDefaults if app group is not available
  static var shared: UserDefaults {
    AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
  }

  /// Migrate existing UserDefaults to app group
  static func migrateToAppGroup() {
    guard let groupDefaults = AppGroupConfiguration.sharedDefaults else {
      print("❌ UserDefaults: Unable to access app group defaults")
      return
    }

    let standardDefaults = UserDefaults.standard
    let keysToMigrate = [
      UserDefaultsKeys.volume,
      UserDefaultsKeys.appearance,
      UserDefaultsKeys.accentColor,
      UserDefaultsKeys.autoPlayOnLaunch,
      UserDefaultsKeys.hideInactiveSounds,
      UserDefaultsKeys.enableSpatialAudio,
      UserDefaultsKeys.language,
      UserDefaultsKeys.mixWithOthers,
      UserDefaultsKeys.volumeWithOtherAudio,
      UserDefaultsKeys.showSoundNames,
      UserDefaultsKeys.iconSize,
      UserDefaultsKeys.soloModeSoundFileName,
      UserDefaultsKeys.showingListView,
      UserDefaultsKeys.showProgressBorder,
      UserDefaultsKeys.lockPortraitOrientationiOS,
      UserDefaultsKeys.quickMixSoundFileNames,
      "savedSoundStates",  // From AudioManager
      "presets",  // From PresetManager
      "customArtworkIds",  // From PresetManager
    ]

    var migratedCount = 0
    for key in keysToMigrate {
      if let value = standardDefaults.object(forKey: key),
        groupDefaults.object(forKey: key) == nil
      {
        groupDefaults.set(value, forKey: key)
        migratedCount += 1
      }
    }

    if migratedCount > 0 {
      groupDefaults.synchronize()
      print("✅ UserDefaults: Migrated \(migratedCount) values to app group")
    }
  }
}
