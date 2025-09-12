//
//  AudioManager+SwiftData.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Combine
import Foundation
import SwiftData

extension AudioManager {
  // MARK: - SwiftData Integration

  /// Set up the model context for accessing custom sounds
  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    CustomSoundManager.shared.setModelContext(context)
    setupCustomSoundObservers()

    // Load custom sounds - they need to be loaded after built-in sounds
    Task { @MainActor in
      loadCustomSounds()

      // Initialize PresetManager after custom sounds are loaded
      await PresetManager.shared.initializePresetManager()
    }
  }

  func setupCustomSoundObservers() {
    // Observe custom sound changes
    customSoundObserver = NotificationCenter.default.publisher(for: .customSoundAdded)
      .merge(with: NotificationCenter.default.publisher(for: .customSoundDeleted))
      .sink { [weak self] notification in
        Task { @MainActor in
          self?.loadCustomSounds()

          // Auto-add newly imported sounds to current preset
          if notification.name == .customSoundAdded {
            self?.addNewSoundToCurrentPreset()
          }
        }
      }
  }

  /// Automatically add newly imported sounds to the current preset
  @MainActor
  private func addNewSoundToCurrentPreset() {
    guard let currentPreset = PresetManager.shared.currentPreset,
      !currentPreset.isDefault
    else {
      print("🎛️ AudioManager: No current custom preset to add new sound to")
      return
    }

    // Get the newest sound (last in the list after loading)
    guard let newestSound = sounds.last else {
      print("🎛️ AudioManager: No sounds available to add to preset")
      return
    }

    print(
      "🎛️ AudioManager: Auto-adding '\(newestSound.fileName)' to current preset '\(currentPreset.displayName)'"
    )

    // Add the new sound to the current preset as unselected
    newestSound.isSelected = false
    newestSound.volume = 1.0

    // This will trigger the preset update via the existing observer
    PresetManager.shared.updateCurrentPresetState()
  }
}
