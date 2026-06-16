//
//  AppSetup.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import Foundation
import SwiftData
import SwiftUI
import os

/// Shared SwiftData container management to ensure single container per process
class SharedModelContainer {
  static let shared = SharedModelContainer()
  private var containerInstance: ModelContainer?

  private init() {}

  var container: ModelContainer {
    guard let containerInstance = containerInstance else {
      fatalError("SharedModelContainer: Container not initialized. Call initialize() first.")
    }
    return containerInstance
  }

  @MainActor
  var mainContext: ModelContext {
    return container.mainContext
  }

  func initialize() {
    guard containerInstance == nil else {
      Logger.app.debug(
        "SharedModelContainer: Already initialized, skipping duplicate initialization")
      return
    }

    Logger.app.debug("SharedModelContainer: Creating SwiftData model container...")
    containerInstance = AppSetup.createModelContainer()

    // Validate that the container is properly initialized
    guard containerInstance != nil else {
      fatalError("SharedModelContainer: Container creation returned nil")
    }

    Logger.app.debug("SharedModelContainer: Successfully initialized shared container")
  }

  var isInitialized: Bool {
    return containerInstance != nil
  }
}

/// Handles shared app initialization and setup
struct AppSetup {
  let modelContainer: ModelContainer

  /// Outcome of opening the persistent store, for optional UI signalling.
  /// Always set once during launch; the degraded cases are also logged.
  enum StoreState: Equatable {
    /// On-disk store opened normally.
    case healthy
    /// Couldn't open this launch (likely transient). Running in-memory for this
    /// session only — the on-disk data is untouched and is retried next launch.
    case temporaryInMemory
    /// A store that failed to open across launches was moved aside and replaced
    /// with a fresh one. Saved artwork rehydrates from the app-group file
    /// mirror, and custom sounds reconcile from their file mirror; the
    /// quarantined store is kept for salvage.
    case recoveredFreshStore
  }

  /// Set once during launch by `createModelContainer()`; read-only afterwards.
  /// Main-actor isolated because the UI reads it (see `SharedAppModifiers`); the
  /// launch writes go through `recordStoreState`.
  @MainActor static var storeState: StoreState = .healthy

  private static let storeFailureCountKey = "swiftDataStoreOpenFailureCount"

  /// Record the launch store state. `createModelContainer()` always runs on the
  /// main thread at launch (App init / app-delegate launch / CarPlay connect), so
  /// it's safe to assert main-actor isolation here rather than hop actors during
  /// container creation.
  private static func recordStoreState(_ state: StoreState) {
    MainActor.assumeIsolated { storeState = state }
  }

  /// What to do after a store-open failure, by how many launches in a row it has
  /// failed. The first failure gets the benefit of the doubt (likely transient);
  /// a failure that recurs is treated as corruption. Pure so the policy is unit
  /// tested without forcing a real container failure.
  enum StoreRecoveryAction: Equatable {
    case retryInMemory
    case quarantineAndRebuild
  }

  static func recoveryAction(forConsecutiveFailures failures: Int) -> StoreRecoveryAction {
    failures >= 2 ? .quarantineAndRebuild : .retryInMemory
  }

  /// Initialize the SwiftData container.
  ///
  /// Uses an explicit versioned schema + migration plan so schema changes
  /// migrate deterministically instead of via SwiftData's silent auto-inference
  /// (the documented cause of the prior artwork wipe).
  ///
  /// Recovery policy (so a store failure never silently looks like permanent
  /// data loss forever): a *single* open failure is given the benefit of the
  /// doubt as transient and degrades to in-memory for the session, leaving the
  /// on-disk store untouched to retry next launch. A failure that *recurs*
  /// across launches is treated as corruption — the store is moved aside (never
  /// deleted) and rebuilt, so the app self-heals instead of showing an empty
  /// library every launch.
  static func createModelContainer() -> ModelContainer {
    let schema = Schema(versionedSchema: BlankieSchemaV1.self)
    AppGroupConfiguration.setupDirectories()

    do {
      let container = try makeOnDiskContainer(schema: schema)
      resetStoreFailureCount()
      recordStoreState(.healthy)
      Logger.app.debug("AppSetup: Successfully created SwiftData model container")
      return container
    } catch {
      let failures = incrementStoreFailureCount()
      Logger.app.error(
        "AppSetup: Failed to open SwiftData store (consecutive failure #\(failures)): \(error.localizedDescription, privacy: .public)"
      )

      // Recurring failure ⇒ the on-disk store is persistently unreadable. Move
      // it aside and rebuild. Presets/settings (UserDefaults) are unaffected and
      // saved artwork rehydrates from the app-group file mirror.
      if recoveryAction(forConsecutiveFailures: failures) == .quarantineAndRebuild,
        let storeURL = AppGroupConfiguration.dataStoreURL
      {
        quarantineStore(at: storeURL)
        if let fresh = try? makeOnDiskContainer(schema: schema) {
          resetStoreFailureCount()
          recordStoreState(.recoveredFreshStore)
          Logger.app.error(
            "AppSetup: Quarantined an unreadable store and created a fresh one; saved artwork will rehydrate from the file mirror"
          )
          return fresh
        }
      }

      // First failure (likely transient), or even the rebuild failed: degrade to
      // in-memory for this session only. The on-disk store is left in place and
      // retried next launch — never crash-loop the launch.
      recordStoreState(.temporaryInMemory)
      Logger.app.error(
        "AppSetup: Running in-memory this session — on-disk data is preserved and retried next launch"
      )
      return makeInMemoryContainer(schema: schema)
    }
  }

  /// Build the on-disk container in the shared app-group store (or the default
  /// per-app store if the app group is unavailable).
  private static func makeOnDiskContainer(schema: Schema) throws -> ModelContainer {
    let modelConfiguration: ModelConfiguration
    if let storeURL = AppGroupConfiguration.dataStoreURL {
      // No file protection so the store opens before first unlock (headless
      // CarPlay cold start), matching the rest of the app's storage.
      try FileManager.default.createDirectory(
        at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.none])
      modelConfiguration = ModelConfiguration(url: storeURL)
      Logger.app.debug("AppSetup: Using app group store at: \(storeURL.path)")
    } else {
      modelConfiguration = ModelConfiguration()
      Logger.app.debug("AppSetup: App group not available, using default store location")
    }
    return try ModelContainer(
      for: schema, migrationPlan: BlankieMigrationPlan.self, configurations: modelConfiguration)
  }

  /// Last-resort in-memory container. If even this fails the runtime itself is
  /// broken and there is nothing to recover.
  private static func makeInMemoryContainer(schema: Schema) -> ModelContainer {
    do {
      return try ModelContainer(
        for: schema, migrationPlan: BlankieMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    } catch {
      fatalError("AppSetup: Failed to create in-memory SwiftData container: \(error)")
    }
  }

  /// Move a persistently-unreadable store (and its `-wal`/`-shm` sidecars) into
  /// a `CorruptedStore` folder beside it. Moved, never deleted, so a future
  /// build or manual tool can still salvage it. Keeps only the most recent copy.
  private static func quarantineStore(at storeURL: URL) {
    let fileManager = FileManager.default
    let quarantineDir = storeURL.deletingLastPathComponent()
      .appendingPathComponent("CorruptedStore", isDirectory: true)
    try? fileManager.removeItem(at: quarantineDir)
    do {
      try fileManager.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
      for suffix in ["", "-wal", "-shm"] {
        let source = URL(fileURLWithPath: storeURL.path + suffix)
        guard fileManager.fileExists(atPath: source.path) else { continue }
        try? fileManager.moveItem(
          at: source, to: quarantineDir.appendingPathComponent(source.lastPathComponent))
      }
      Logger.app.error("AppSetup: Moved unreadable store aside to CorruptedStore/")
    } catch {
      Logger.app.error(
        "AppSetup: Failed to quarantine unreadable store: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  /// Consecutive on-disk store-open failures across launches (app-group
  /// UserDefaults, so it survives in-place updates). Reset on a successful open.
  /// Not private so the persistence is unit tested.
  static func incrementStoreFailureCount() -> Int {
    let count = UserDefaults.shared.integer(forKey: storeFailureCountKey) + 1
    UserDefaults.shared.set(count, forKey: storeFailureCountKey)
    return count
  }

  static func resetStoreFailureCount() {
    if UserDefaults.shared.integer(forKey: storeFailureCountKey) != 0 {
      UserDefaults.shared.removeObject(forKey: storeFailureCountKey)
    }
  }

  /// Setup all managers with model context from the shared container
  @MainActor
  func setupManagers() {
    // Use the shared model container from the app initialization
    // This ensures we have only ONE container for the entire process
    AudioManager.shared.setModelContext(modelContainer.mainContext)

    // Pass model context to PresetArtworkManager
    PresetArtworkManager.shared.setModelContext(modelContainer.mainContext)

    // Warm artwork cache
    Task {
      await PresetArtworkManager.shared.warmCache()
    }

    // Cache thumbnails for CarPlay
    #if os(iOS)
      Task {
        await PresetManager.shared.cacheAllThumbnails()
      }
    #endif

    // Load custom sounds and initialize PresetManager. This runs on every
    // platform/scheme: it fires when a UI scene appears, which is the only
    // trigger for macOS and the iOS *Universal* build. The CarPlay build also
    // calls loadCustomSoundsWhenReady() from its AppDelegate to cover a
    // headless CarPlay cold-start (no UI scene), so on that build a normal
    // launch reaches this point twice. That overlap is safe because
    // loadCustomSoundsWhenReady() is idempotent: its `hasLoadedCustomSounds`
    // guard skips re-instantiating custom Sound objects (re-creating them
    // would orphan the originals the active preset/UI still holds, leaving
    // them playing with no way to stop them), while still (re-)initializing
    // PresetManager. Without this call, PresetManager.isLoading never clears
    // and the preset picker is stuck on "Loading Presets…". The model context
    // was set just above, so the load can proceed immediately.
    Task { @MainActor in
      await AudioManager.shared.loadCustomSoundsWhenReady()
    }
  }
}
