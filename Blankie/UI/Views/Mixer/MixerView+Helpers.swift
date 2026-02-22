//
//  MixerView+Helpers.swift
//  Blankie
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension MixerView {
    // Calculate filtered sounds based on current preset
    var filteredSounds: [Sound] {
      return filterSounds()
    }

    private func filterSounds() -> [Sound] {
      let visibleSounds = audioManager.getVisibleSounds()

      let filteredSounds = visibleSounds.filter { sound in
        // Check if sound is included in current preset
        if let currentPreset = presetManager.currentPreset {
          // For default preset, show all sounds
          if currentPreset.isDefault {
            return true
          } else {
            // For custom presets, only show sounds that are part of the preset
            return currentPreset.soundStates.contains { $0.fileName == sound.fileName }
          }
        } else {
          // No current preset - show all sounds
          return true
        }
      }

      // Sort filtered sounds according to preset order or default sound order
      if let currentPreset = presetManager.currentPreset,
         !currentPreset.isDefault,
         let soundOrder = currentPreset.soundOrder
      {
        // Use preset's sound order for custom presets
        print("🔍 FilteredSounds: Using preset order: \(soundOrder)")
        let orderDict = Dictionary(uniqueKeysWithValues: soundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      } else {
        // Use default sound order for default preset or no preset
        print("🔍 FilteredSounds: Using default order: \(audioManager.defaultSoundOrder)")
        let orderDict = Dictionary(
          uniqueKeysWithValues: audioManager.defaultSoundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      }
    }

    // Determine if we're on iPad or Mac
    var isLargeDevice: Bool {
      horizontalSizeClass == .regular
    }

    // MARK: - Helper Properties

    var hasSelectedSounds: Bool {
      audioManager.hasSelectedSounds
    }
  }
#endif
