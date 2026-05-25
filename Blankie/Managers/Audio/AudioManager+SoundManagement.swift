//
//  AudioManager+SoundManagement.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import Foundation
import SwiftData

extension AudioManager {
  // MARK: - Sound Management

  @MainActor
  func getVisibleSounds() -> [Sound] {
    sounds
  }

  /// Move a sound to a new position
  func moveSound(from sourceIndex: Int, to destinationIndex: Int) {
    guard sourceIndex < sounds.count && destinationIndex <= sounds.count else {
      return
    }

    // Move sound in the array
    let movedSound = sounds.remove(at: sourceIndex)
    sounds.insert(movedSound, at: min(destinationIndex, sounds.count))

    objectWillChange.send()
    debugLog(
      "🎵 AudioManager: Moved sound '\(movedSound.fileName)' from \(sourceIndex) to \(destinationIndex)"
    )
  }

  /// Move a visible sound to a new position
  @MainActor
  func moveVisibleSound(from sourceIndex: Int, to destinationIndex: Int) {
    moveSound(from: sourceIndex, to: destinationIndex)
  }

  /// Move visible sounds from source indices to destination (for List's onMove)
  @MainActor
  func moveVisibleSounds(from source: IndexSet, to destination: Int) {
    sounds.move(fromOffsets: source, toOffset: destination)
    objectWillChange.send()
    debugLog("🎵 AudioManager: Moved sounds from \(source) to \(destination)")
  }

  /// Apply volume settings to all playing sounds by triggering volume updates
  func applyVolumeSettings() {
    debugLog("🎵 AudioManager: Updating volumes for volume settings change")

    for sound in sounds where sound.isSelected {
      // Trigger volume recalculation which will include custom volume settings
      sound.updateVolume()
    }
  }
}
