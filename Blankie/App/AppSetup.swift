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
      print("⚠️ SharedModelContainer: Already initialized, skipping duplicate initialization")
      return
    }

    print("🗄️ SharedModelContainer: Creating SwiftData model container...")
    containerInstance = AppSetup.createModelContainer()

    // Validate that the container is properly initialized
    guard containerInstance != nil else {
      fatalError("❌ SharedModelContainer: Container creation returned nil")
    }

    print("✅ SharedModelContainer: Successfully initialized shared container")
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
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true, attributes: attributes)

        // Configure SwiftData to use the app group URL
        modelConfiguration = ModelConfiguration(url: storeURL)
        print("🗄️ AppSetup: Using app group store at: \(storeURL.path)")
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
