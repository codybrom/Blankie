//
//  PresetManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import Combine
import SwiftUI

#if os(iOS)
  import UIKit
#endif

class PresetManager: ObservableObject {
  private var isInitializing = true
  static let shared = PresetManager()

  @Published private(set) var presets: [Preset] = []
  @Published private(set) var currentPreset: Preset? {
    didSet {
      AudioManager.shared.updateNowPlayingInfoForPreset(
        presetName: currentPreset?.activeTitle,
        creatorName: currentPreset?.creatorName,
        artworkData: currentPreset?.artworkData
      )
    }
  }
  @Published private(set) var hasCustomPresets: Bool = false
  @Published private(set) var isLoading: Bool = true
  @Published private(set) var error: Error?

  private var cancellables = Set<AnyCancellable>()
  private var isInitialLoad = true

  private init() {
    print("\n🎛️ PresetManager: --- Begin Initialization ---")

    // Set up a single observer for state changes
    AudioManager.shared.$sounds
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.updateCurrentPresetState()  // Remove await
        }
      }
      .store(in: &cancellables)

    // Don't load presets immediately - wait for custom sounds to be loaded
    // This will be triggered by initializePresetManager() after AudioManager setup
    print("🎛️ PresetManager: --- End Initialization (deferred preset loading) ---\n")
  }

  /// Initialize preset manager after AudioManager has loaded all sounds (including custom)
  @MainActor
  func initializePresetManager() async {
    guard isInitializing else {
      print("🎛️ PresetManager: Already initialized, skipping")
      return
    }

    print("🎛️ PresetManager: --- Begin Preset Loading After Sound Setup ---")
    await loadPresets()
    isInitializing = false
    print("🎛️ PresetManager: --- End Preset Loading After Sound Setup ---\n")
  }

  // Helper methods for extensions to set private properties
  func setLoading(_ loading: Bool) {
    isLoading = loading
  }

  func setPresets(_ newPresets: [Preset]) {
    presets = newPresets
  }

  func updatePresetAtIndex(_ index: Int, with preset: Preset) {
    presets[index] = preset
  }

  func setCurrentPreset(_ preset: Preset?) {
    currentPreset = preset
  }

  func setInitialLoad(_ initial: Bool) {
    isInitialLoad = initial
  }

  func setError(_ error: Error?) {
    self.error = error
  }

  func setHasCustomPresets(_ has: Bool) {
    hasCustomPresets = has
  }

  deinit {
    cancellables.forEach { $0.cancel() }
    print("🎛️ PresetManager: Cleaned up")
  }
}

// MARK: - Lifecycle Observers

extension PresetManager {
  private func setupObservers() {
    // Observe app lifecycle for state changes that might affect presets
    #if os(iOS)
      NotificationCenter.default
        .publisher(for: UIApplication.willTerminateNotification)
        .sink { [weak self] _ in
          Task { @MainActor in
            self?.savePresets()
          }
        }
        .store(in: &cancellables)

      // Observe audio manager for state changes that might affect presets
      NotificationCenter.default
        .publisher(for: UIApplication.didEnterBackgroundNotification)
        .sink { [weak self] _ in
          Task { @MainActor in
            self?.savePresets()
          }
        }
        .store(in: &cancellables)
    #endif
  }

}

// MARK: - Preset CRUD Operations

extension PresetManager {

  @MainActor
  func updatePreset(_ preset: Preset, newName: String) {
    print("\n🎛️ PresetManager: Updating preset '\(preset.name)' to '\(newName)'")

    guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
      handleError(PresetError.invalidPreset)
      return
    }

    var updatedPreset = preset
    updatedPreset.name = newName
    updatedPreset.lastModifiedVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // Validate the updated preset
    guard updatedPreset.validate() else {
      handleError(PresetError.invalidPreset)
      return
    }

    presets[index] = updatedPreset

    if currentPreset?.id == preset.id {
      currentPreset = updatedPreset
    }

    savePresets()
    print("🎛️ PresetManager: Preset updated successfully\n")
  }

  @MainActor
  func deletePreset(_ preset: Preset) {
    print("\n🎛️ PresetManager: --- Begin Delete Preset ---")
    print("🎛️ PresetManager: Attempting to delete preset '\(preset.name)'")

    guard !preset.isDefault else {
      handleError(PresetError.invalidPreset)
      return
    }

    let wasCurrentPreset = (currentPreset?.id == preset.id)

    presets.removeAll { $0.id == preset.id }
    updateCustomPresetStatus()

    if wasCurrentPreset {
      print("🎛️ PresetManager: Deleted current preset, switching to default/next")

      // Find next available CUSTOM preset
      if let nextCustomPreset = presets.first(where: { !$0.isDefault }) {
        do {
          print("🎛️ PresetManager: Applying next custom preset '\(nextCustomPreset.name)'")
          try applyPreset(nextCustomPreset)
        } catch {
          handleError(error)
        }
      } else {
        // If no other custom presets exist, copy the deleted preset's state to the default preset
        if let defaultPresetIndex = presets.firstIndex(where: { $0.isDefault }) {
          // Copy current state
          var updatedDefaultPreset = presets[defaultPresetIndex]
          updatedDefaultPreset.soundStates = preset.soundStates
          presets[defaultPresetIndex] = updatedDefaultPreset
          currentPreset = nil

          do {
            print(
              "🎛️ PresetManager: No other custom presets. Updating default and setting current preset to nil."
            )
            try applyPreset(updatedDefaultPreset)
          } catch {
            handleError(error)
          }

        } else {
          print("🎛️ PresetManager: No default or custom presets to switch too after deletion")
        }
      }
    }

    savePresets()
    print("🎛️ PresetManager: --- End Delete Preset ---\n")
  }

}

// MARK: - Preset State Management

extension PresetManager {
  @MainActor
  func clearCurrentPreset() {
    currentPreset = nil
  }

  @MainActor
  func updateCurrentPresetState() {
    // Don't update during initialization
    if isInitializing { return }

    guard let preset = currentPreset else {
      // Only log this once, not repeatedly
      if !isInitializing {
        print("❌ PresetManager: No current preset to update")
      }
      return
    }

    // Get current state based on preset type
    let newStates: [PresetState]
    let currentSoundOrder: [String]

    if preset.isDefault {
      // For default preset, include all sounds
      newStates = AudioManager.shared.sounds.map { sound in
        PresetState(
          fileName: sound.fileName,
          isSelected: sound.isSelected,
          volume: sound.volume
        )
      }
      currentSoundOrder = AudioManager.shared.sounds
        .sorted { $0.customOrder < $1.customOrder }
        .map(\.fileName)
    } else {
      // For custom presets, only update sounds that are in the preset
      newStates = preset.soundStates.compactMap { existingState in
        if let sound = AudioManager.shared.sounds.first(where: {
          $0.fileName == existingState.fileName
        }) {
          return PresetState(
            fileName: existingState.fileName,
            isSelected: sound.isSelected,
            volume: sound.volume
          )
        }
        return nil  // Remove sounds that no longer exist
      }
      // For custom presets, only track order of sounds in the preset
      let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
      currentSoundOrder = AudioManager.shared.sounds
        .filter { presetSoundFileNames.contains($0.fileName) }
        .sorted { $0.customOrder < $1.customOrder }
        .map(\.fileName)
    }

    // Only update if state or order has actually changed
    let orderChanged = preset.soundOrder != currentSoundOrder
    if preset.soundStates != newStates || orderChanged {
      var updatedPreset = preset
      updatedPreset.soundStates = newStates
      updatedPreset.soundOrder = currentSoundOrder
      updatedPreset.lastModifiedVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

      if let index = presets.firstIndex(where: { $0.id == preset.id }) {
        presets[index] = updatedPreset
        currentPreset = updatedPreset
        savePresets()
      }
    }
  }

  @MainActor
  func applyPreset(_ preset: Preset, isInitialLoad: Bool = false) throws {
    logPresetApplication(preset)

    guard preset.validate() else {
      throw PresetError.invalidPreset
    }

    if preset.id == currentPreset?.id && !isInitialLoad {
      print("🎛️ PresetManager: Preset already active, but still updating Now Playing info")
      print(
        "🎨 PresetManager: Artwork data: \(preset.artworkData != nil ? "✅ \(preset.artworkData!.count) bytes" : "❌ None")"
      )
      // Still update Now Playing info for artwork changes
      AudioManager.shared.updateNowPlayingInfoForPreset(
        presetName: preset.activeTitle,
        creatorName: preset.creatorName,
        artworkData: preset.artworkData
      )
      return
    }

    let targetStates = preset.soundStates
    let wasPlaying = AudioManager.shared.isGloballyPlaying

    // Update current preset before any audio changes
    currentPreset = preset
    PresetStorage.saveLastActivePresetID(preset.id)

    // Explicitly update Now Playing info with preset name, creator, and artwork
    print(
      "🎨 PresetManager: Updating Now Playing with artwork: \(preset.artworkData != nil ? "✅ \(preset.artworkData!.count) bytes" : "❌ None")"
    )
    AudioManager.shared.updateNowPlayingInfoForPreset(
      presetName: preset.activeTitle,
      creatorName: preset.creatorName,
      artworkData: preset.artworkData
    )

    Task {
      if wasPlaying {
        AudioManager.shared.pauseAll()
        try? await Task.sleep(nanoseconds: 300_000_000)
      }

      // Apply states all at once
      applySoundStates(targetStates)

      // Apply custom sound order if preset has one
      if let soundOrder = preset.soundOrder {
        applySoundOrder(soundOrder)
      }

      // Wait a bit for states to settle
      try? await Task.sleep(nanoseconds: 100_000_000)

      // Start playing if:
      // 1. Not an initial load (user manually selected preset)
      // 2. OR initial load and auto-play is enabled
      let shouldAutoPlay = !isInitialLoad || GlobalSettings.shared.autoPlayOnLaunch

      if shouldAutoPlay && targetStates.contains(where: { $0.isSelected }) {
        AudioManager.shared.setGlobalPlaybackState(true)
      }
    }

    print("🎛️ PresetManager: --- End Apply Preset ---\n")
  }

  /// Remove deleted custom sounds from all presets
  @MainActor
  func cleanupDeletedCustomSounds() {
    print("🎛️ PresetManager: Cleaning up deleted custom sounds from presets")

    // Get current valid sound file names
    let validSoundFileNames = Set(AudioManager.shared.sounds.map(\.fileName))

    // Update each preset to remove invalid sound states
    for (index, preset) in presets.enumerated() {
      let validSoundStates = preset.soundStates.filter { soundState in
        validSoundFileNames.contains(soundState.fileName)
      }

      // Only update if there were changes
      if validSoundStates.count != preset.soundStates.count {
        var updatedPreset = preset
        updatedPreset.soundStates = validSoundStates
        presets[index] = updatedPreset

        // Update current preset if needed
        if currentPreset?.id == preset.id {
          currentPreset = updatedPreset
        }

        print(
          "🎛️ PresetManager: Removed \(preset.soundStates.count - validSoundStates.count) deleted sounds from preset '\(preset.name)'"
        )
      }
    }

    // Save the cleaned up presets
    savePresets()
  }

}
