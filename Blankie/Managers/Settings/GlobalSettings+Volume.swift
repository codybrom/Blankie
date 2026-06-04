//
//  GlobalSettings+Volume.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Foundation

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
    debugLog("GlobalSettings: Saved volume: \(validVolume)")
  }
}
