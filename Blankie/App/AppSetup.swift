//
//  AppSetup.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import Foundation
import SwiftData
import SwiftUI

/// Shared SwiftData container management to ensure single container per process
@MainActor
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

  var mainContext: ModelContext {
    return container.mainContext
  }

  func initialize() {
    guard containerInstance == nil else {
      print("⚠️ SharedModelContainer: Already initialized, skipping duplicate initialization")
      return
    }

    print("🗄️ SharedModelContainer: Creating SwiftData model container...")
    containerInstance = AppSetup.createModelContainer()

    // Validate that the container is properly initialized
    guard let container = containerInstance else {
      fatalError("❌ SharedModelContainer: Container creation returned nil")
    }

    // Additional validation: ensure mainContext is accessible
    _ = container.mainContext // This will fail fast if there are issues
    print("✅ SharedModelContainer: Successfully initialized and validated shared container")
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
        // Configure file protection for CarPlay compatibility
        // This allows data access even when the device is locked
        let configuration = ModelConfiguration(
          url: storeURL,
          allowsSave: true,
          isStoredInMemoryOnly: false,
          isAutosaveEnabled: true
        )

        // Set file protection attributes for the store directory
        try setCarPlayCompatibleFileProtection(for: storeURL)

        modelConfiguration = configuration
        print("🗄️ AppSetup: Using app group store with CarPlay protection at: \(storeURL.path)")
      } else {
        modelConfiguration = ModelConfiguration()
        print("⚠️ AppSetup: App group not available, using default store location")
      }

      let container = try ModelContainer(
        for: CustomSoundData.self, PresetArtwork.self,
        configurations: modelConfiguration
      )
      print("🗄️ AppSetup: Successfully created SwiftData model container")
      return container
    } catch {
      fatalError("❌ AppSetup: Failed to create SwiftData model container: \(error)")
    }
  }

  /// Configure file protection for CarPlay compatibility
  private static func setCarPlayCompatibleFileProtection(for storeURL: URL) throws {
    let storeDirectory = storeURL.deletingLastPathComponent()

    // Set file protection to allow access before first unlock
    // This is essential for CarPlay when the device is locked
    let attributes: [FileAttributeKey: Any] = [
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
    ]

    try FileManager.default.setAttributes(attributes, ofItemAtPath: storeDirectory.path)
    print("🚗 AppSetup: Set CarPlay-compatible file protection for store directory")
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
  }
}
