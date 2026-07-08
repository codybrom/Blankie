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

  /// Load all sounds (built-in + custom) after initialization is complete, so
  /// PresetManager gets complete sound data. Single-flight: every caller joins
  /// the one in-flight bootstrap task rather than starting its own load. A run
  /// that finished before a model context existed (built-ins-only early path)
  /// retries once a context is set, so custom sounds can't stay unloaded.
  @MainActor
  func loadCustomSoundsWhenReady() async {
    // Join the in-flight bootstrap. A run that finished before a model context
    // existed (built-ins-only early path) needs a retry once one is set — but
    // only ONE caller may start it, or concurrent waiters each spawn a second
    // full load (re-instantiating the custom Sound objects the active preset
    // still holds). After awaiting, the caller that still sees the just-finished
    // task claims the retry; any other waiter loops and joins the task that
    // caller installed rather than starting its own.
    while let task = launchBootstrapTask {
      let generation = launchBootstrapGeneration
      await task.value
      if hasLoadedCustomSounds || modelContext == nil { return }
      // No new task was installed while we awaited: we claim the retry. If the
      // generation moved, another caller already installed one — loop and join.
      if launchBootstrapGeneration == generation { break }
    }
    launchBootstrapGeneration += 1
    let task = Task { @MainActor in await performLaunchBootstrap() }
    launchBootstrapTask = task
    await task.value
  }

  /// The launch bootstrap body. Only one instance ever runs at a time (serialized
  /// by `loadCustomSoundsWhenReady`'s single-flight task), so the
  /// `hasLoadedCustomSounds` read/set gap can't race a concurrent caller into a
  /// second full load.
  @MainActor
  private func performLaunchBootstrap() async {
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
    // This allows CarPlay to function when the device is locked. UIApplication.shared
    // is unavailable in app extensions (e.g. the widget extension, which also shares
    // this file to run App Intents in-process), hence the WIDGET_EXTENSION guard.
    #if !os(macOS) && !WIDGET_EXTENSION
      if !UIApplication.shared.isProtectedDataAvailable {
        Logger.audio.debug(
          "AudioManager: Protected data not available, attempting to load custom sounds anyway for CarPlay"
        )
      }
    #endif

    // Whether a previous no-context run already initialized PresetManager (and
    // cleared its "Loading Presets…" spinner) with built-in sounds only. If so,
    // re-apply the current preset after the late custom sounds load below.
    // `isLoading` is PresetManager's public proxy for that state (it clears
    // together with the private `isInitializing` at the end of `loadPresets()`).
    let presetManagerWasAlreadyInitialized = !PresetManager.shared.isLoading

    // Load custom sounds once. Serialized by the single-flight task, so this
    // read/set of `hasLoadedCustomSounds` can't race a concurrent caller.
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
      // Back-fill mirrors for sounds saved before mirroring existed, so existing
      // libraries gain durability without waiting for an edit.
      CustomSoundManager.shared.syncAllMirrors()

      // Custom sounds arrived after a built-ins-only early path already applied
      // the current preset; re-apply it so they pick up their saved
      // selection/volume. Autoplay-gated by `isGloballyPlaying`, so this cannot
      // start audio on its own. Runs before `reconcileLaunchPlaybackState()` so a
      // deferred solo restore still runs last and wins.
      if presetManagerWasAlreadyInitialized,
        let preset = PresetManager.shared.currentPreset
      {
        PresetManager.shared.applySoundStates(preset.soundStates)
      }
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
    // Custom sounds may be unavailable this session (SwiftData fell back to an
    // in-memory store, or the rows haven't loaded). Union the loaded sounds with
    // the SwiftData rows so a row that exists but didn't load as a Sound is still
    // valid. If no rows are visible yet a solo favorite points at a non-built-in
    // sound, that's a likely transient load failure, not a deletion — pass nil so
    // solo favorites are kept rather than irreversibly pruned (mirrors the bail
    // in PresetManager.cleanupDeletedCustomSounds).
    let customRowNames = Set(CustomSoundManager.shared.getAllCustomSounds().map { $0.fileName })
    let validNames = Set(sounds.map { $0.fileName }).union(customRowNames)
    let soloFavoriteIsUnknown = GlobalSettings.shared.starredItems.contains { token in
      guard let fileName = GlobalSettings.soloFileName(fromToken: token) else { return false }
      return !validNames.contains(fileName)
    }
    let validSoundFileNames: Set<String>? =
      (customRowNames.isEmpty && soloFavoriteIsUnknown) ? nil : validNames

    GlobalSettings.shared.pruneStarredItems(
      validPresetIDs: Set(PresetManager.shared.presets.map { $0.id.uuidString }),
      validSoundFileNames: validSoundFileNames)

    let hadSavedSolo = GlobalSettings.shared.getSavedSoloModeFileName() != nil
    let soloRestored = restoreSoloModeIfNeeded(soundsFullyLoaded: true)
    if hadSavedSolo, !soloRestored, soloModeSound == nil, !isGloballyPlaying {
      applyPresetLaunchState()
    }
  }

  #if !os(macOS) && !WIDGET_EXTENSION
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

}
