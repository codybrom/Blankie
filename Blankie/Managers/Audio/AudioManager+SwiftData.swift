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
      // Restore any rows lost to a store rebuild from their file mirror before
      // loading, so recovered sounds reappear this launch.
      await CustomSoundManager.shared.reconcileCustomSoundsFromDisk()
      loadCustomSounds()
      hasLoadedCustomSounds = true
      // Back-fill mirrors for sounds saved before mirroring existed, so existing
      // libraries gain durability without waiting for an edit.
      CustomSoundManager.shared.syncAllMirrors()
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
