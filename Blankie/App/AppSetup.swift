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

/// Owns the one SwiftData container for the process.
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

    guard containerInstance != nil else {
      fatalError("SharedModelContainer: Container creation returned nil")
    }

    Logger.app.debug("SharedModelContainer: Successfully initialized shared container")
  }

  var isInitialized: Bool {
    return containerInstance != nil
  }
}

struct AppSetup {
  let modelContainer: ModelContainer

  /// Outcome of opening the persistent store at launch.
  enum StoreState: Equatable {
    case healthy
    /// Running in memory this session. The on-disk store is untouched and retried next launch.
    case temporaryInMemory
    /// The unreadable store was quarantined and replaced. Artwork and custom sounds
    /// restore from their app-group file mirrors.
    case recoveredFreshStore
  }

  /// Set once at launch by `createModelContainer()`. Main-actor because
  /// `SharedAppModifiers` reads it.
  @MainActor static var storeState: StoreState = .healthy

  /// Whether this launch found a legacy store it couldn't copy into the app group.
  /// The migrator sets it at launch on the main thread, before store setup reads it.
  nonisolated(unsafe) static var storeCopyPending = false

  private static let storeFailureCountKey = "swiftDataStoreOpenFailureCount"

  /// `createModelContainer()` always runs on the main thread at launch (App init,
  /// app delegate or CarPlay connect), so main-actor isolation can be assumed.
  private static func recordStoreState(_ state: StoreState) {
    MainActor.assumeIsolated { storeState = state }
  }

  /// Recovery step after a store-open failure, by consecutive failed launches.
  /// Pure so the policy is unit tested without a real container failure.
  enum StoreRecoveryAction: Equatable {
    case retryInMemory
    case quarantineAndRebuild
  }

  static func recoveryAction(forConsecutiveFailures failures: Int) -> StoreRecoveryAction {
    failures >= 2 ? .quarantineAndRebuild : .retryInMemory
  }

  /// Opens the shared SwiftData store. A first failure falls back to an in-memory
  /// container for the session. A second consecutive failure quarantines the
  /// unreadable store to `CorruptedStore/` and creates a fresh on-disk store.
  /// The versioned schema and migration plan keep SwiftData from inferring migrations.
  static func createModelContainer() -> ModelContainer {
    let schema = Schema(versionedSchema: BlankieSchemaV1.self)
    AppGroupConfiguration.setupDirectories()

    // The legacy store couldn't be copied in. A new store at the destination
    // would end the retry and strand it, so run in memory until a launch copies it.
    if storeCopyPending {
      recordStoreState(.temporaryInMemory)
      Logger.app.error(
        "AppSetup: Store migration pending; running in-memory so the next launch retries the copy")
      return makeInMemoryContainer(schema: schema)
    }

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

      // Presets and settings live in UserDefaults, and saved artwork restores
      // from the app-group file mirror.
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

      // First failure, or the rebuild failed. The on-disk store stays in place
      // for the next launch.
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

  /// Last-resort container. A failure here is unrecoverable.
  private static func makeInMemoryContainer(schema: Schema) -> ModelContainer {
    do {
      return try ModelContainer(
        for: schema, migrationPlan: BlankieMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    } catch {
      fatalError("AppSetup: Failed to create in-memory SwiftData container: \(error)")
    }
  }

  /// Moves an unreadable store and its `-wal`/`-shm` sidecars into `CorruptedStore/`
  /// beside it for salvage. Keeps only the most recent copy.
  static func quarantineStore(at storeURL: URL) {
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

  /// Consecutive store-open failures across launches, kept in app-group UserDefaults.
  /// Internal so the persistence is unit tested.
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

  @MainActor
  func setupManagers() {
    AudioManager.shared.setModelContext(modelContainer.mainContext)
    PresetArtworkManager.shared.setModelContext(modelContainer.mainContext)

    Task {
      await PresetArtworkManager.shared.warmCache()
    }

    // Cache thumbnails for CarPlay
    #if os(iOS)
      Task {
        await PresetManager.shared.cacheAllThumbnails()
      }
    #endif

    // Safe to overlap other callers (see `loadCustomSoundsWhenReady()`).
    Task { @MainActor in
      await AudioManager.shared.loadCustomSoundsWhenReady()
    }
  }
}

extension AppSetup {
  /// Loads custom sounds and presets for an App Intent that runs before any scene
  /// appears. Safe to call redundantly (see `loadCustomSoundsWhenReady()`).
  @MainActor
  static func ensureManagersReadyForIntents() async {
    if !SharedModelContainer.shared.isInitialized {
      SharedModelContainer.shared.initialize()
    }
    // The system runs entity queries every few seconds. Setting the contexts
    // again re-subscribes the custom-sound observers each time.
    if AudioManager.shared.modelContext == nil {
      AudioManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
      PresetArtworkManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
    }
    await AudioManager.shared.loadCustomSoundsWhenReady()
  }
}
