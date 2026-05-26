//
//  AppSetup.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import Foundation
import SwiftData
import SwiftUI
import TipKit

/// Shared SwiftData container management to ensure single container per process
class SharedModelContainer {
  static let shared = SharedModelContainer()
  private var containerInstance: ModelContainer?

  private init() {}

  var container: ModelContainer {
    guard let containerInstance = containerInstance else {
      fatalError("❌ SharedModelContainer: Container not initialized. Call initialize() first.")
    }
    return containerInstance
  }

  @MainActor
  var mainContext: ModelContext {
    return container.mainContext
  }

  func initialize() {
    guard containerInstance == nil else {
      debugLog("⚠️ SharedModelContainer: Already initialized, skipping duplicate initialization")
      return
    }

    debugLog("🗄️ SharedModelContainer: Creating SwiftData model container...")
    containerInstance = AppSetup.createModelContainer()

    // Validate that the container is properly initialized
    guard containerInstance != nil else {
      fatalError("❌ SharedModelContainer: Container creation returned nil")
    }

    debugLog("✅ SharedModelContainer: Successfully initialized shared container")
  }

  var isInitialized: Bool {
    return containerInstance != nil
  }
}

/// Handles shared app initialization and setup
struct AppSetup {
  let modelContainer: ModelContainer

  /// Initialize SwiftData container
  static func createModelContainer() -> ModelContainer {
    do {
      // Ensure app group directories exist
      AppGroupConfiguration.setupDirectories()

      // Create model configuration with app group URL
      var modelConfiguration: ModelConfiguration
      if let storeURL = AppGroupConfiguration.dataStoreURL {
        let storeDirectory = storeURL.deletingLastPathComponent()

        // Create directory with no file protection
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.none]
        try FileManager.default.createDirectory(
          at: storeDirectory, withIntermediateDirectories: true, attributes: attributes)

        // Configure SwiftData to use the app group URL
        modelConfiguration = ModelConfiguration(url: storeURL)
        debugLog("🗄️ AppSetup: Using app group store at: \(storeURL.path)")
      } else {
        modelConfiguration = ModelConfiguration()
        debugLog("⚠️ AppSetup: App group not available, using default store location")
      }

      let container = try ModelContainer(
        for: CustomSoundData.self, PresetArtwork.self,
        configurations: modelConfiguration
      )

      debugLog("🗄️ AppSetup: Successfully created SwiftData model container")
      return container
    } catch {
      fatalError("❌ AppSetup: Failed to create SwiftData model container: \(error)")
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

    // Configure TipKit for preset onboarding
    configureTipKit()
  }

  /// Configure TipKit for the app
  @MainActor
  private func configureTipKit() {
    #if DEBUG
      // Reset tips in debug builds for testing
      try? Tips.resetDatastore()
    #endif

    // Configure TipKit
    try? Tips.configure([
      .displayFrequency(.immediate),
      .datastoreLocation(.applicationDefault),
    ])

    debugLog("✅ AppSetup: TipKit configured for preset onboarding")
  }
}
