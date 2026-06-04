//
//  AudioManager+Persistence.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Foundation

extension AudioManager {
  func loadSavedState() {
    guard let state = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]] else {
      return
    }
    for savedState in state {
      guard let fileName = savedState["fileName"] as? String,
        let sound = sounds.first(where: { $0.fileName == fileName })
      else {
        continue
      }
      // Only update if values have actually changed to avoid unnecessary processing
      let savedIsSelected = savedState["isSelected"] as? Bool ?? false
      let savedVolume = savedState["volume"] as? Float ?? 1.0

      if sound.isSelected != savedIsSelected {
        sound.isSelected = savedIsSelected
      }
      if sound.volume != savedVolume {
        sound.volume = savedVolume
      }
    }
  }

  func saveState() {
    // Don't save state during Quick Mix mode - volume changes are temporary
    guard !isQuickMix else {
      debugLog("🚗 AudioManager: Skipping state save during Quick Mix mode")
      return
    }

    let state = sounds.map { sound in
      [
        "id": sound.id.uuidString,
        "fileName": sound.fileName,
        "isSelected": sound.isSelected,
        "volume": sound.volume,
      ]
    }
    UserDefaults.shared.set(state, forKey: "soundState")
  }

  func updateDefaultSoundOrder(from source: IndexSet, to destination: Int) {
    defaultSoundOrder.move(fromOffsets: source, toOffset: destination)
    UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
    objectWillChange.send()
    debugLog("🎵 AudioManager: Updated default sound order - moved from \(source) to \(destination)")
  }
}
