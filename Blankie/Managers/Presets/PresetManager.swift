//
//  PresetManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import Combine
import Foundation
import SwiftUI

class PresetManager: ObservableObject {
  private var isInitializing = true
  static let shared = PresetManager()

  @Published private(set) var presets: [Preset] = []
  @Published var currentPreset: Preset? {
    didSet {
      AudioManager.shared.updateNowPlayingInfoForPreset(
        preset: currentPreset,
        presetName: currentPreset?.activeTitle,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId
      )
    }
  }

  @Published private(set) var hasCustomPresets: Bool = false
  @Published private(set) var isLoading: Bool = true
  @Published private(set) var error: Error?

  private var cancellables = Set<AnyCancellable>()
  private var isInitialLoad = true

  // In-flight prefetch for nearby preset animated artwork; cancelled when the
  // current preset changes so stale prefetches don't compete with the new one.
  private var nearbyArtworkPrefetchTask: Task<Void, Never>?

  private init() {
    print("\n🎛️ PresetManager: --- Begin Initialization ---")

    // Set up a single observer for state changes
    AudioManager.shared.$sounds
      .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.updateCurrentPresetState()
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

    // Cache thumbnails for CarPlay after presets are loaded
    print("🖼️ PresetManager: Caching thumbnails for CarPlay...")
    await cacheAllThumbnails()

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
    // Observe app lifecycle for state changes that might affect presets using SwiftUI scene phase
    // This should be handled by SwiftUI's .onChange(of: scenePhase) in the app's main view
    // Rather than using UIKit notifications directly
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

    cleanupAnimatedArtworkFiles(for: preset)

    let wasCurrentPreset = (currentPreset?.id == preset.id)

    presets.removeAll { $0.id == preset.id }
    updateCustomPresetStatus()

    // Remove cached thumbnail
    removeThumbnail(for: preset.id)

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
    if isInitializing { return }

    guard let preset = currentPreset else {
      if !isInitializing {
        print("❌ PresetManager: No current preset to update")
      }
      return
    }

    let (newStates, currentSoundOrder) = generateUpdatedPresetData(for: preset)
    updatePresetIfChanged(
      preset: preset, newStates: newStates, currentSoundOrder: currentSoundOrder
    )
  }

  /// Get recently used presets for caching
  func getRecentPresets(limit: Int = 5) -> [Preset] {
    // For now, return first N presets - could be enhanced to track actual usage
    return Array(presets.prefix(limit))
  }

  private func generateUpdatedPresetData(for preset: Preset) -> ([PresetState], [String]) {
    // Get the file names of sounds that should be in this preset
    let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))

    // Only include sounds that are part of this preset
    let newStates = AudioManager.shared.sounds
      .filter { presetSoundFileNames.contains($0.fileName) }
      .map { sound in
        PresetState(
          fileName: sound.fileName,
          isSelected: sound.isSelected,
          volume: sound.volume
        )
      }

    // Preserve the preset's existing sound order, don't use global customOrder
    // If the preset has an existing order, use it; otherwise use the order from soundStates
    let currentSoundOrder = preset.soundOrder ?? preset.soundStates.map(\.fileName)

    return (newStates, currentSoundOrder)
  }

  @MainActor private func updatePresetIfChanged(
    preset: Preset, newStates: [PresetState], currentSoundOrder: [String]
  ) {
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

  private func cleanupAnimatedArtworkFiles(for preset: Preset) {
    AnimatedArtworkFileStore.removeItemIfExists(relativePath: preset.animatedArtwork?.loopPath)
    if preset.animatedArtwork?.previewPath != preset.staticArtworkPath {
      AnimatedArtworkFileStore.removeItemIfExists(relativePath: preset.animatedArtwork?.previewPath)
    }
    AnimatedArtworkFileStore.removeItemIfExists(relativePath: preset.staticArtworkPath)
  }

  @MainActor
  func applyPreset(_ preset: Preset, isInitialLoad: Bool = false, forceReapply: Bool = false) throws {
    logPresetApplication(preset)

    guard preset.validate() else {
      throw PresetError.invalidPreset
    }

    if preset.id == currentPreset?.id, !isInitialLoad, !forceReapply {
      handleAlreadyActivePreset(preset)
      return
    }

    preparePresetApplication(preset)
    executePresetApplication(preset: preset, isInitialLoad: isInitialLoad)

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

  @MainActor
  func updateCurrentPresetSoundOrder(from source: IndexSet, to destination: Int) {
    guard let preset = currentPreset else {
      print("❌ PresetManager: No current preset to update sound order")
      return
    }

    print("🎛️ PresetManager: Updating sound order for preset '\(preset.name)'")
    print("  - Moving from indices: \(source) to destination: \(destination)")

    // Get the current order of sounds in the preset
    var soundOrder = preset.soundOrder ?? preset.soundStates.map(\.fileName)

    // Filter to only include sounds that are actually in the preset
    let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
    soundOrder = soundOrder.filter { presetSoundFileNames.contains($0) }

    // Debug: Print the sound being moved
    for index in source {
      if index < soundOrder.count {
        print("  - Moving sound: '\(soundOrder[index])' from index \(index)")
      } else {
        print("  - WARNING: Index \(index) out of bounds for soundOrder count \(soundOrder.count)")
      }
    }

    // Apply the move
    soundOrder.move(fromOffsets: source, toOffset: destination)

    // Update the preset
    var updatedPreset = preset
    updatedPreset.soundOrder = soundOrder
    updatedPreset.lastModifiedVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // Update in the presets array
    if let index = presets.firstIndex(where: { $0.id == preset.id }) {
      presets[index] = updatedPreset
      currentPreset = updatedPreset
      savePresets()

      print("🎛️ PresetManager: Updated sound order for preset '\(preset.name)'")
      print("  - New order: \(soundOrder)")
    }
  }

  @MainActor
  func updateCurrentPresetWithOrder(_ newOrder: [String]) {
    guard let preset = currentPreset else {
      print("❌ PresetManager: No current preset to update sound order")
      return
    }

    print("🎛️ PresetManager: Updating sound order for preset '\(preset.name)'")
    print("  - New order: \(newOrder)")

    // Update the preset
    var updatedPreset = preset
    updatedPreset.soundOrder = newOrder
    updatedPreset.lastModifiedVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // Update in the presets array
    if let index = presets.firstIndex(where: { $0.id == preset.id }) {
      presets[index] = updatedPreset
      currentPreset = updatedPreset
      savePresets()

      // Force UI update
      objectWillChange.send()

      print("🎛️ PresetManager: Successfully updated sound order")

      // Verify the update
      if let verifyPreset = presets.first(where: { $0.id == preset.id }) {
        print("🎛️ PresetManager: Verified saved order: \(verifyPreset.soundOrder ?? [])")
      }
    } else {
      print("❌ PresetManager: Failed to find preset in array!")
    }
  }
}

// MARK: - Application Helpers

extension PresetManager {
  @MainActor func handleAlreadyActivePreset(_ preset: Preset) {
    print("🎛️ PresetManager: Preset already active, but still updating Now Playing info")
    print(
      "🎨 PresetManager: Artwork ID: \(preset.artworkId != nil ? "✅ \(preset.artworkId!)" : "❌ None")"
    )
    AudioManager.shared.updateNowPlayingInfoForPreset(
      preset: preset,
      presetName: preset.activeTitle,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId
    )
  }

  @MainActor func preparePresetApplication(_ preset: Preset) {
    currentPreset = preset
    PresetStorage.saveLastActivePresetID(preset.id)

    // Pre-cache artwork for instant display
    Task {
      await PresetArtworkManager.shared.preCacheArtwork(for: preset)
    }

    print(
      "🎨 PresetManager: Updating Now Playing with artwork ID: \(preset.artworkId != nil ? "✅ \(preset.artworkId!)" : "❌ None")"
    )
    AudioManager.shared.updateNowPlayingInfoForPreset(
      preset: preset,
      presetName: preset.activeTitle,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId
    )
  }

  func executePresetApplication(preset: Preset, isInitialLoad: Bool) {
    let targetStates = preset.soundStates
    let wasPlaying = AudioManager.shared.isGloballyPlaying

    Task { @MainActor in
      if wasPlaying {
        AudioManager.shared.pauseAll()
        // Allow audio system to process pause before applying new sounds
        await Task.yield()
      }

      applySoundStates(targetStates)

      // Allow sound states to be applied before autoplay
      await Task.yield()

      let shouldAutoPlay = !isInitialLoad || GlobalSettings.shared.autoPlayOnLaunch
      if shouldAutoPlay, targetStates.contains(where: { $0.isSelected }) {
        AudioManager.shared.setGlobalPlaybackState(true)
      }

      // Prefetch animated artwork for nearby presets so they're available on lock screen
      prefetchNearbyAnimatedArtwork(currentPreset: preset)
    }
  }

  /// Prefetch animated artwork ODR resources for next/previous presets
  /// This ensures animated artwork is available when switching presets on lock screen
  private func prefetchNearbyAnimatedArtwork(currentPreset: Preset) {
    #if os(iOS)
      // Get sorted list of custom presets (same logic as next/previous navigation)
      let customPresets = presets
        .filter { !$0.isDefault }
        .sorted {
          let order1 = $0.order ?? Int.max
          let order2 = $1.order ?? Int.max
          return order1 < order2
        }

      guard !customPresets.isEmpty else { return }

      // Find current preset index
      guard let currentIndex = customPresets.firstIndex(where: { $0.id == currentPreset.id }) else {
        return
      }

      // Get next and previous presets (wrapping around)
      let nextIndex = (currentIndex + 1) % customPresets.count
      let prevIndex = currentIndex > 0 ? currentIndex - 1 : customPresets.count - 1

      let nextPreset = customPresets[nextIndex]
      let prevPreset = customPresets[prevIndex]

      // Collect bundled ODR identifiers from nearby presets
      var odrIds: [String] = []

      if let nextAnimated = nextPreset.animatedArtwork,
         nextAnimated.source == .bundled,
         let bundledId = nextAnimated.bundledIdentifier
      {
        odrIds.append(bundledId)
      }

      if let prevAnimated = prevPreset.animatedArtwork,
         prevAnimated.source == .bundled,
         let bundledId = prevAnimated.bundledIdentifier
      {
        odrIds.append(bundledId)
      }

      guard !odrIds.isEmpty else { return }

      print("🎛️ PresetManager: Prefetching \(odrIds.count) animated artwork resources for nearby presets")

      // Cancel any stale prefetch from the previous current-preset.
      nearbyArtworkPrefetchTask?.cancel()
      nearbyArtworkPrefetchTask = Task {
        await OnDemandResourceManager.shared.preloadResources(odrIds)
      }
    #endif
  }
}

// MARK: - Helper Methods

extension PresetManager {
  func handleError(_ error: Error) {
    print("❌ PresetManager: Error occurred: \(error.localizedDescription)")
    setError(error)
  }

  func updateCustomPresetStatus() {
    setHasCustomPresets(presets.contains { !$0.isDefault })
  }

  func createDefaultPreset() -> Preset {
    print("🎛️ PresetManager: Creating new default preset")
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    return Preset(
      id: UUID(),
      name: "Default",
      soundStates: AudioManager.shared.sounds.map { sound in
        PresetState(
          fileName: sound.fileName,
          isSelected: false,
          volume: 1.0
        )
      },
      isDefault: true,
      createdVersion: currentVersion,
      lastModifiedVersion: currentVersion,
      soundOrder: AudioManager.shared.sounds.map(\.fileName),
      creatorName: nil,
      artworkId: nil,
      animatedArtwork: nil,
      staticArtworkPath: nil,
      order: nil,
      isImported: nil,
      originalId: nil
    )
  }

  func logPresetState(_ preset: Preset) {
    print("  - Name: '\(preset.name)'")
    print("  - ID: \(preset.id)")
    print("  - Is Default: \(preset.isDefault)")

    // Only log active sounds
    let activeStates = preset.soundStates.filter { $0.isSelected }
    if !activeStates.isEmpty {
      print("  - Active Sounds:")
      for state in activeStates {
        print("    * \(state.fileName) (Volume: \(state.volume))")
      }
    }
  }

  func logPresetApplication(_ preset: Preset) {
    print("\n🎛️ PresetManager: --- Begin Apply Preset ---")
    print("🎛️ PresetManager: Applying preset '\(preset.name)':")
    print("  - ID: \(preset.id)")
    print("  - Is Default: \(preset.isDefault)")
    print("  - Active Sounds:")
    preset.soundStates
      .filter { $0.isSelected }.forEach { state in
        print("    * \(state.fileName) (Volume: \(state.volume))")
      }
  }

  @MainActor
  func applySoundStates(_ targetStates: [PresetState]) {
    // Get the file names of sounds that should be in this preset
    let presetSoundFileNames = Set(targetStates.map(\.fileName))

    // Handle solo mode if active
    if let soloSound = AudioManager.shared.soloModeSound {
      // Check if the solo sound is part of this preset
      let soloSoundInPreset = presetSoundFileNames.contains(soloSound.fileName)

      if soloSoundInPreset {
        // Solo sound is part of the preset - keep it playing without restart
        // Just exit solo mode, the sound will continue playing
        AudioManager.shared.exitSoloModeWithoutResuming()
      } else {
        // Solo sound is NOT part of the preset - must stop it
        soloSound.isSelected = false
        soloSound.pause()
        AudioManager.shared.exitSoloModeWithoutResuming()
      }
    }

    // First, disable all sounds that are NOT in this preset
    for sound in AudioManager.shared.sounds {
      if !presetSoundFileNames.contains(sound.fileName), sound.isSelected {
        print("  - Disabling '\(sound.fileName)' (not in preset)")
        sound.isSelected = false
      }
    }

    // Then, apply the states for sounds that ARE in this preset
    for state in targetStates {
      if let sound = AudioManager.shared.sounds.first(where: { $0.fileName == state.fileName }) {
        let selectionChanged = sound.isSelected != state.isSelected
        let volumeChanged = sound.volume != state.volume

        if selectionChanged || volumeChanged {
          print("  - Configuring '\(sound.fileName)':")
          if selectionChanged {
            print("    * Selection: \(sound.isSelected) -> \(state.isSelected)")
          }
          if volumeChanged {
            print("    * Volume: \(sound.volume) -> \(state.volume)")
          }

          sound.isSelected = state.isSelected
          sound.volume = state.volume
        }
      }
    }
  }
}

// MARK: - Persistence

extension PresetManager {
  @MainActor
  func loadPresets() async {
    print("\n🎛️ PresetManager: --- Begin Loading Presets ---")
    setLoading(true)

    do {
      // Load or create default preset
      let defaultPreset = PresetStorage.loadDefaultPreset() ?? createDefaultPreset()
      setPresets([defaultPreset])

      // Load custom presets
      let customPresets = PresetStorage.loadCustomPresets()
      if !customPresets.isEmpty {
        var allPresets = presets
        allPresets.append(contentsOf: customPresets)
        setPresets(allPresets)
      }

      // Migrate any presets that contain old sound names with file extensions
      migratePresetSoundNames()

      // Ensure all custom presets have order values
      ensurePresetOrder()

      updateCustomPresetStatus()

      // Load last active preset or default
      if let lastID = PresetStorage.loadLastActivePresetID() {
        print("🎛️ PresetManager: Found last active preset ID: \(lastID)")
        if let lastPreset = presets.first(where: { $0.id == lastID }) {
          print("🎛️ PresetManager: ✅ Found matching preset: '\(lastPreset.name)'")
          print("\n🎛️ PresetManager: Loading last active preset:")
          logPresetState(lastPreset)
          try applyPreset(lastPreset, isInitialLoad: true)
          print("🎛️ PresetManager: ✅ Successfully applied last active preset '\(lastPreset.name)'")
        } else {
          print("❌ PresetManager: Last active preset ID \(lastID) not found in loaded presets")
          print("🎛️ PresetManager: Available presets: \(presets.map { "\($0.name) (\($0.id))" })")
          print("🎛️ PresetManager: Falling back to default preset")
          try applyPreset(presets[0], isInitialLoad: true)
        }
      } else {
        print("🎛️ PresetManager: No last active preset ID found, applying default")
        try applyPreset(presets[0], isInitialLoad: true)
      }
    } catch {
      handleError(error)
    }

    setLoading(false)
    setInitialLoad(false)
    print("🎛️ PresetManager: --- End Loading Presets ---\n")
  }

  @MainActor
  func savePresets() {
    // Skip saving during initialization - nothing has actually changed
    guard !isInitializing else {
      print("🎛️ PresetManager: Skipping save during initialization")
      return
    }

    print("\n🎛️ PresetManager: --- Begin Saving Presets ---")

    updateCurrentPresetBeforeSave()
    performActualSave()

    print("🎛️ PresetManager: --- End Saving Presets ---\n")
  }

  @MainActor
  private func updateCurrentPresetBeforeSave() {
    // Update current preset's state before saving
    if let currentPreset = currentPreset,
       let index = presets.firstIndex(where: { $0.id == currentPreset.id })
    {
      // Get the preset from the array to preserve any updates (like order)
      var updatedPreset = presets[index]
      // For custom presets, only update sounds that are already in the preset
      if !updatedPreset.isDefault {
        updatedPreset.soundStates = updatedPreset.soundStates.map { existingState in
          // Find the current sound state
          if let sound = AudioManager.shared.sounds.first(where: {
            $0.fileName == existingState.fileName
          }) {
            return PresetState(
              fileName: existingState.fileName,
              isSelected: sound.isSelected,
              volume: sound.volume
            )
          }
          return existingState
        }
      } else {
        // For default preset, include all sounds
        updatedPreset.soundStates = AudioManager.shared.sounds.map { sound in
          PresetState(
            fileName: sound.fileName,
            isSelected: sound.isSelected,
            volume: sound.volume
          )
        }
      }
      updatePresetAtIndex(index, with: updatedPreset)
      setCurrentPreset(updatedPreset)

      print("Saving current preset state for '\(updatedPreset.name)':")
      print("  - Active sounds:")
      updatedPreset.soundStates
        .filter { $0.isSelected }
        .forEach { state in
          print("    * \(state.fileName) (Volume: \(state.volume))")
        }
    }
  }

  @MainActor
  private func performActualSave() {
    let defaultPreset = presets.first { $0.isDefault }
    let customPresets = presets.filter { !$0.isDefault }

    // Move file I/O to background queue to prevent UI blocking
    Task.detached {
      if let defaultPreset = defaultPreset {
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
      PresetStorage.saveCustomPresets(customPresets)
    }

    // Cache thumbnails for quick access
    Task {
      await cacheAllThumbnails()
    }
  }

  /// Migrates preset sound names from old format (with file extensions) to new format (without extensions)
  private func migratePresetSoundNames() {
    let legacyExtensions = ["mp3", "m4a", "wav", "aiff"]
    var migratedPresets = [Preset]()
    var hasMigrations = false

    for preset in presets {
      var migratedSoundStates = [PresetState]()
      var presetHasMigrations = false

      for soundState in preset.soundStates {
        var migratedFileName = soundState.fileName

        // Check if this fileName has a legacy extension
        for ext in legacyExtensions where soundState.fileName.hasSuffix(".\(ext)") {
          migratedFileName = soundState.fileName.replacingOccurrences(of: ".\(ext)", with: "")
          presetHasMigrations = true
          print(
            "🔄 PresetManager: Migrating sound name in preset '\(preset.name)': '\(soundState.fileName)' -> '\(migratedFileName)'"
          )
          break
        }

        migratedSoundStates.append(
          PresetState(
            fileName: migratedFileName,
            isSelected: soundState.isSelected,
            volume: soundState.volume
          ))
      }

      if presetHasMigrations {
        var migratedPreset = preset
        migratedPreset.soundStates = migratedSoundStates
        migratedPresets.append(migratedPreset)
        hasMigrations = true
      } else {
        migratedPresets.append(preset)
      }
    }

    if hasMigrations {
      setPresets(migratedPresets)
      print("🔄 PresetManager: Preset migration completed, saving updated presets")

      // Save the migrated presets immediately
      let defaultPreset = migratedPresets.first { $0.isDefault }
      let customPresets = migratedPresets.filter { !$0.isDefault }

      if let defaultPreset = defaultPreset {
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
      PresetStorage.saveCustomPresets(customPresets)
    }
  }

  /// Ensures all custom presets have unique order values assigned
  @MainActor
  private func ensurePresetOrder() {
    var needsSave = false
    var updatedPresets = presets

    // Get custom presets
    let customPresets = updatedPresets.filter { !$0.isDefault }

    // Check for duplicates or nil order values
    var orderValues = Set<Int>()
    var hasDuplicates = false

    for preset in customPresets {
      if let order = preset.order {
        if orderValues.contains(order) {
          hasDuplicates = true
          print("🎛️ PresetManager: Found duplicate order value: \(order)")
          break
        }
        orderValues.insert(order)
      }
    }

    // Check if any custom preset is missing order or has duplicates
    let hasUnorderedPresets = customPresets.contains { $0.order == nil } || hasDuplicates

    if hasUnorderedPresets {
      print("🎛️ PresetManager: Reassigning order values to all custom presets")

      // Sort custom presets by current order (if exists) then by name
      let sortedCustomPresets = customPresets.sorted { preset1, preset2 in
        // First sort by existing order if both have it
        if let order1 = preset1.order, let order2 = preset2.order {
          return order1 < order2
        }
        // Put presets with order before those without
        if preset1.order != nil, preset2.order == nil {
          return true
        }
        if preset1.order == nil, preset2.order != nil {
          return false
        }
        // Fall back to name comparison
        return preset1.name < preset2.name
      }

      // Assign sequential order values to all custom presets
      for (index, preset) in sortedCustomPresets.enumerated() where preset.order != index {
        var updatedPreset = preset
        updatedPreset.order = index
        print(
          "🎛️ PresetManager: Updating order for '\(preset.name)' from \(preset.order ?? -1) to \(index)"
        )

        if let presetIndex = updatedPresets.firstIndex(where: { $0.id == preset.id }) {
          updatedPresets[presetIndex] = updatedPreset
          needsSave = true
        }
      }

      if needsSave {
        setPresets(updatedPresets)
        savePresets()
      }
    }
  }
}

// MARK: - Thumbnails

extension PresetManager {
  /// Cache a small thumbnail for quick access
  @MainActor
  func cacheThumbnail(for preset: Preset) async {
    #if os(iOS)
      guard let artworkId = preset.artworkId else { return }

      // Check if thumbnail is already cached
      let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"
      let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
      if userDefaults.data(forKey: thumbnailKey) != nil {
        return // Already cached
      }

      // Load the full artwork
      guard let artworkData = await PresetArtworkManager.shared.loadArtworkData(id: artworkId),
            let fullImage = UIImage(data: artworkData)
      else { return }

      // Generate a thumbnail for CarPlay (44x44 points)
      let thumbnailSize = CGSize(width: 44, height: 44)

      UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0)
      fullImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
      let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()

      // Cache the thumbnail in app group UserDefaults for CarPlay access
      if let thumbnail = thumbnail,
         let thumbnailData = thumbnail.pngData()
      {
        userDefaults.set(thumbnailData, forKey: thumbnailKey)
        print("🖼️ PresetManager: Cached thumbnail for preset '\(preset.displayName)'")
      }
    #endif
  }

  /// Cache thumbnails for all presets
  @MainActor
  func cacheAllThumbnails() async {
    // Don't cache if we're still loading
    guard !isLoading else {
      print("⚠️ PresetManager: Skipping thumbnail cache - still loading")
      return
    }

    for preset in presets {
      await cacheThumbnail(for: preset)
    }
  }

  /// Remove cached thumbnail when preset is deleted
  func removeThumbnail(for _: UUID) {
    // Let PresetArtworkManager handle its own cache cleanup
    // No need for manual UserDefaults cleanup
  }
}
