//
//  AppSetup.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import SwiftData
import SwiftUI

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

  /// Setup all managers with model context
  @MainActor
  func setupManagers() {
    // Pass model context to AudioManager for custom sounds
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
