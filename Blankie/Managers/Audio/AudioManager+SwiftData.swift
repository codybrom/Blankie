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
import os

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
      Logger.audio.debug("AudioManager: Loading built-in sounds first...")
      loadSounds()
    }

    guard modelContext != nil else {
      Logger.audio.debug("AudioManager: Model context not ready - built-in sounds only")
      // Initialize PresetManager with built-in sounds only
      await PresetManager.shared.initializePresetManager()
      reconcileLaunchPlaybackState()
      return
    }

    // For CarPlay, try to load custom sounds even if protected data isn't available
    // This allows CarPlay to function when the device is locked
    #if !os(macOS)
      if !UIApplication.shared.isProtectedDataAvailable {
        Logger.audio.debug(
          "AudioManager: Protected data not available, attempting to load custom sounds anyway for CarPlay"
        )
      }
    #endif

    // Load custom sounds once. This can be called more than once at launch
    // (the CarPlay build fires it from IOSAppDelegate, and AppSetup fires it
    // for every scheme); a second full load would tear down and re-create the
    // custom Sound objects the active preset/UI already holds, leaving the
    // originals playing with no way to stop them. PresetManager still gets
    // (re-)initialized below in either case.
    if hasLoadedCustomSounds {
      Logger.audio.debug("AudioManager: Custom sounds already loaded, skipping reload")
    } else {
      Logger.audio.debug("AudioManager: Loading custom sounds with SwiftData coordination...")
      loadCustomSounds()
      hasLoadedCustomSounds = true
    }

    // Initialize PresetManager with ALL sounds loaded
    await PresetManager.shared.initializePresetManager()

    reconcileLaunchPlaybackState()
  }

  /// Once every sound and preset is loaded, drop favorites whose target no
  /// longer exists, and finish (or abandon) a deferred solo restore — falling
  /// back to the preset if the saved solo sound turns out to be gone. Runs on
  /// every `loadCustomSoundsWhenReady()` path (including the no-model-context
  /// one); it's idempotent and safe to re-run.
  @MainActor
  private func reconcileLaunchPlaybackState() {
    GlobalSettings.shared.pruneStarredItems(
      validPresetIDs: Set(PresetManager.shared.presets.map { $0.id.uuidString }),
      validSoundFileNames: Set(sounds.map { $0.fileName }))

    let hadSavedSolo = GlobalSettings.shared.getSavedSoloModeFileName() != nil
    let soloRestored = restoreSoloModeIfNeeded(soundsFullyLoaded: true)
    if hadSavedSolo, !soloRestored, soloModeSound == nil, !isGloballyPlaying {
      applyPresetLaunchState()
    }
  }

  #if !os(macOS)
    /// Wait for protected data to become available before accessing SwiftData
    /// This prevents crashes during CarPlay cold start on locked devices
    @MainActor
    private func waitForProtectedDataAvailability() async {
      guard !UIApplication.shared.isProtectedDataAvailable else {
        Logger.audio.debug("AudioManager: Protected data already available")
        return
      }

      Logger.audio.debug("AudioManager: Protected data not available, waiting...")

      // Use AsyncStream for Swift 6 compliance
      for await _ in NotificationCenter.default.notifications(
        named: UIApplication.protectedDataDidBecomeAvailableNotification)
      {
        Logger.audio.debug("AudioManager: Protected data became available")
        break
      }
    }
  #endif

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

          // Scrub the just-deleted sound from every preset now (loadCustomSounds
          // has already rebuilt `sounds` without it). The load's own cleanup is
          // deferred 5s, so without this a delete-then-quit could leave a preset
          // referencing a missing sound — which fails validation at next launch.
          if notification.name == .customSoundDeleted {
            PresetManager.shared.cleanupDeletedCustomSounds()
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
      Logger.audio.debug("AudioManager: No current custom preset to add new sound to")
      return
    }

    // Get the newest sound (last in the list after loading)
    guard let newestSound = sounds.last else {
      Logger.audio.debug("AudioManager: No sounds available to add to preset")
      return
    }

    Logger.audio.debug(
      "AudioManager: Auto-adding '\(newestSound.fileName)' to current preset '\(currentPreset.displayName)'"
    )

    // Add the new sound to the current preset as unselected
    newestSound.isSelected = false
    newestSound.volume = 1.0

    // This will trigger the preset update via the existing observer
    PresetManager.shared.updateCurrentPresetState()
  }
}
