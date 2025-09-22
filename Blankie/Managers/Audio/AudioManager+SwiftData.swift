//
//  AudioManager+SwiftData.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Combine
import Foundation
import SwiftData
import SwiftUI

extension AudioManager {
  // MARK: - SwiftData Integration

  /// Set up the model context for accessing custom sounds
  /// CRITICAL: Must be called on @MainActor to prevent SwiftData actor violations
  @MainActor
  func setModelContext(_ context: ModelContext) {
    modelContext = context
    CustomSoundManager.shared.setModelContext(context)
    setupCustomSoundObservers()
  }

  /// Load all sounds (built-in + custom) after initialization is complete
  /// This ensures PresetManager gets complete sound data
  @MainActor
  func loadCustomSoundsWhenReady() async {
    // Load built-in sounds first if not already loaded
    if sounds.isEmpty {
      print("🎵 AudioManager: Loading built-in sounds first...")
      loadSounds()
    }

    guard modelContext != nil else {
      print("⚠️ AudioManager: Model context not ready - built-in sounds only")
      // Initialize PresetManager with built-in sounds only
      await PresetManager.shared.initializePresetManager()
      return
    }

    // For CarPlay, try to load custom sounds even if protected data isn't available
    // This allows CarPlay to function when the device is locked
    if !UIApplication.shared.isProtectedDataAvailable {
      print("⚠️ AudioManager: Protected data not available, attempting to load custom sounds anyway for CarPlay")
    }

    // Load custom sounds to complete the sound library
    print("🎵 AudioManager: Loading custom sounds with SwiftData coordination...")
    loadCustomSounds()

    // Initialize PresetManager with ALL sounds loaded
    await PresetManager.shared.initializePresetManager()
  }

  /// Wait for protected data to become available before accessing SwiftData
  /// This prevents crashes during CarPlay cold start on locked devices
  @MainActor
  private func waitForProtectedDataAvailability() async {
    guard !UIApplication.shared.isProtectedDataAvailable else {
      print("✅ AudioManager: Protected data already available")
      return
    }

    print("⚠️ AudioManager: Protected data not available, waiting...")

    // Use AsyncStream for Swift 6 compliance
    for await _ in NotificationCenter.default.notifications(
      named: UIApplication.protectedDataDidBecomeAvailableNotification)
    {
      print("✅ AudioManager: Protected data became available")
      break
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
