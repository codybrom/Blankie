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

  @MainActor
  func setModelContext(_ context: ModelContext) {
    modelContext = context
    CustomSoundManager.shared.setModelContext(context)
    setupCustomSoundObservers()
  }

  /// Loads built-in and custom sounds, then initializes PresetManager. Every caller joins
  /// one bootstrap task, and a run that finished without a model context retries once one is set.
  @MainActor
  func loadCustomSoundsWhenReady() async {
    // Only the waiter that sees an unchanged generation starts the retry; the
    // others loop and join its task, so custom sounds never load twice.
    while let task = launchBootstrapTask {
      let generation = launchBootstrapGeneration
      await task.value
      if hasLoadedCustomSounds || modelContext == nil { return }
      if launchBootstrapGeneration == generation { break }
    }
    launchBootstrapGeneration += 1
    let task = Task { @MainActor in await performLaunchBootstrap() }
    launchBootstrapTask = task
    await task.value
  }

  /// The bootstrap body. `loadCustomSoundsWhenReady` runs one at a time, so the
  /// `hasLoadedCustomSounds` check can't race a second load.
  @MainActor
  private func performLaunchBootstrap() async {
    if sounds.isEmpty {
      Logger.audio.debug("AudioManager: Loading built-in sounds first...")
      loadSounds()
    }

    guard modelContext != nil else {
      Logger.audio.debug("AudioManager: Model context not ready - built-in sounds only")
      await PresetManager.shared.initializePresetManager()
      reconcileLaunchPlaybackState()
      return
    }

    // Load anyway so CarPlay works while the device is locked. The widget extension
    // compiles this file for App Intents and has no `UIApplication.shared`.
    #if !os(macOS) && !WIDGET_EXTENSION
      if !UIApplication.shared.isProtectedDataAvailable {
        Logger.audio.debug(
          "AudioManager: Protected data not available, attempting to load custom sounds anyway for CarPlay"
        )
      }
    #endif

    // True if a no-context run already initialized PresetManager with built-ins
    // only. `isLoading` clears together with its private `isInitializing`.
    let presetManagerWasAlreadyInitialized = !PresetManager.shared.isLoading

    if hasLoadedCustomSounds {
      Logger.audio.debug("AudioManager: Custom sounds already loaded, skipping reload")
    } else {
      Logger.audio.debug("AudioManager: Loading custom sounds with SwiftData coordination...")
      // Restore any rows lost to a store rebuild from their file mirror before
      // loading, so recovered sounds reappear this launch.
      await CustomSoundManager.shared.reconcileCustomSoundsFromDisk()
      loadCustomSounds()
      customSoundLoadPasses += 1
      hasLoadedCustomSounds = true
      // Back-fill mirrors for sounds saved before mirroring existed.
      CustomSoundManager.shared.syncAllMirrors()

      // Re-apply the preset so late custom sounds get their saved selection and
      // volume (no autoplay). Runs before reconcileLaunchPlaybackState() so a
      // deferred single sound restore wins.
      if presetManagerWasAlreadyInitialized,
        let preset = PresetManager.shared.currentPreset
      {
        PresetManager.shared.applySoundStates(preset.soundStates)
      }
    }

    await PresetManager.shared.initializePresetManager()

    reconcileLaunchPlaybackState()

    // Siri/Shortcuts vocabulary and the Spotlight index need the full library.
    PresetManager.shared.refreshDiscoverableEntitiesIfNeeded()
    // An earlier built-ins-only publish left out custom favorites and pinnable sounds.
    republishWidgetCatalog()
  }

  /// Prunes favorites with missing targets and finishes or abandons a deferred
  /// single sound restore (falling back to the preset). Idempotent; runs on every bootstrap path.
  @MainActor
  private func reconcileLaunchPlaybackState() {
    // A custom row or file counts as valid even if it didn't load as a Sound. No
    // rows plus an unknown single sound favorite reads as a transient load failure, so
    // sound favorites aren't pruned (same bail as cleanupDeletedCustomSounds).
    let customRowNames = Set(CustomSoundManager.shared.getAllCustomSounds().map { $0.fileName })
      .union(CustomSoundManager.shared.customAudioFileNamesOnDisk())
    let validNames = Set(sounds.map { $0.fileName }).union(customRowNames)
    let singleFavoriteIsUnknown = GlobalSettings.shared.starredItems.contains { token in
      guard let fileName = GlobalSettings.singleFileName(fromToken: token) else { return false }
      return !validNames.contains(fileName)
    }
    let validSoundFileNames: Set<String>? =
      (customRowNames.isEmpty && singleFavoriteIsUnknown) ? nil : validNames

    GlobalSettings.shared.pruneStarredItems(
      validPresetIDs: Set(PresetManager.shared.presets.map { $0.id.uuidString }),
      validSoundFileNames: validSoundFileNames)

    let hadSavedSingle = GlobalSettings.shared.getSavedSingleSoundFileName() != nil
    let singleRestored = restoreSingleSoundIfNeeded(soundsFullyLoaded: true)
    if hadSavedSingle, !singleRestored, singleSound == nil, !isGloballyPlaying {
      applyPresetLaunchState()
    }
  }

  #if !os(macOS) && !WIDGET_EXTENSION
    /// Waits for protected data before touching SwiftData, since CarPlay can
    /// cold-start on a locked device.
    @MainActor
    private func waitForProtectedDataAvailability() async {
      guard !UIApplication.shared.isProtectedDataAvailable else {
        Logger.audio.debug("AudioManager: Protected data already available")
        return
      }

      Logger.audio.debug("AudioManager: Protected data not available, waiting...")

      for await _ in NotificationCenter.default.notifications(
        named: UIApplication.protectedDataDidBecomeAvailableNotification)
      {
        Logger.audio.debug("AudioManager: Protected data became available")
        break
      }
    }
  #endif

  func setupCustomSoundObservers() {
    customSoundObserver = NotificationCenter.default.publisher(for: .customSoundAdded)
      .merge(with: NotificationCenter.default.publisher(for: .customSoundDeleted))
      .sink { [weak self] notification in
        Task { @MainActor in
          self?.syncCustomSounds()

          // Scrub presets right away; one referencing a missing sound fails
          // validation at next launch.
          if notification.name == .customSoundDeleted {
            PresetManager.shared.cleanupDeletedCustomSounds()
          }

          // Keeps `PlaySoundIntent` parameters and Spotlight in sync with the sounds.
          PresetManager.shared.refreshDiscoverableEntitiesIfNeeded()
          // Pinnable sounds and single sound favorites in the widgets changed too.
          self?.republishWidgetCatalog()
        }
      }
  }

}
