//
//  GlobalSettings+SoloMode.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import Foundation

extension GlobalSettings {
  @MainActor
  func saveSoloModeSound(fileName: String?) {
    if let fileName = fileName {
      UserDefaults.shared.set(fileName, forKey: UserDefaultsKeys.soloModeSoundFileName)
      debugLog("💾 GlobalSettings: Saved solo mode sound: \(fileName)")
    } else {
      UserDefaults.shared.removeObject(forKey: UserDefaultsKeys.soloModeSoundFileName)
      debugLog("💾 GlobalSettings: Cleared solo mode sound")
    }
  }

  func getSavedSoloModeFileName() -> String? {
    return UserDefaults.shared.string(forKey: UserDefaultsKeys.soloModeSoundFileName)
  }
}
