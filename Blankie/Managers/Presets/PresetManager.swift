//
//  PresetManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import Combine
import Foundation
import SwiftUI
import os

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

  /// The preset whose theme (accent, blur, view mode) should drive the UI, or
  /// nil when none should. Quick Mix already clears `currentPreset`, but solo
  /// mode preserves it so the preset can be restored on exit — and during solo
  /// the preset's theme must not apply (solo has its own app-accent identity).
  /// Centralizing the rule here keeps accent resolution and the Settings
  /// "Overridden by Preset" badges in agreement.
  ///
  /// Views reading this must also observe `AudioManager` so SwiftUI
  /// re-evaluates when solo / Quick Mix state changes.
  @MainActor
  var themingPreset: Preset? {
    let audio = AudioManager.shared
    if audio.soloModeSound != nil || audio.isQuickMix { return nil }
    return currentPreset
  }

  private var cancellables = Set<AnyCancellable>()
  private var isInitialLoad = true

  /// Set by applySoundStates; until then the mixer may not match the preset.
  var presetStatesApplied = false

  // In-flight prefetch for nearby preset animated artwork; cancelled when the
  // current preset changes so stale prefetches don't compete with the new one.
  private var nearbyArtworkPrefetchTask: Task<Void, Never>?

  private init() {
    Logger.presets.debug("PresetManager: --- Begin Initialization ---")

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
    Logger.presets.debug("PresetManager: --- End Initialization (deferred preset loading) ---")
  }

  /// Initialize preset manager after AudioManager has loaded all sounds (including custom)
  @MainActor
  func initializePresetManager() async {
    guard isInitializing else {
      Logger.presets.debug("PresetManager: Already initialized, skipping")
      return
    }

    Logger.presets.debug("PresetManager: --- Begin Preset Loading After Sound Setup ---")
    await loadPresets()

    isInitializing = false

    // Deferred so CarPlay thumbnail caching can't starve the preset-apply task.
    Task(priority: .background) { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      Logger.presets.debug("PresetManager: Caching thumbnails for CarPlay...")
      await self.cacheAllThumbnails()
    }

    Logger.presets.debug("PresetManager: --- End Preset Loading After Sound Setup ---")
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
    Logger.presets.debug("PresetManager: Cleaned up")
  }
}

// MARK: - Preset CRUD Operations

extension PresetManager {
  @MainActor
  func updatePreset(_ preset: Preset, newName: String) {
    Logger.presets.debug("PresetManager: Updating preset '\(preset.name)' to '\(newName)'")

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
    Logger.presets.debug("PresetManager: Preset updated successfully")
  }

  @MainActor
  func deletePreset(_ preset: Preset) {
    Logger.presets.debug("PresetManager: --- Begin Delete Preset ---")
    Logger.presets.debug("PresetManager: Attempting to delete preset '\(preset.name)'")

    guard !preset.isDefault else {
      handleError(PresetError.invalidPreset)
      return
    }

    cleanupAnimatedArtworkFiles(for: preset)

    // Delete the preset's stored artwork rows too — cleanupAnimatedArtworkFiles
    // only removes the on-disk .mov/preview files, leaving the full-resolution
    // PresetArtwork image blobs to accumulate in SwiftData forever otherwise.
    let deletedPresetID = preset.id
    Task { try? await PresetArtworkManager.shared.deleteArtwork(for: deletedPresetID) }

    let wasCurrentPreset = (currentPreset?.id == preset.id)

    presets.removeAll { $0.id == preset.id }
    updateCustomPresetStatus()

    // Drop the deleted preset from favorites so its token doesn't linger in
    // `starredItems`. The iPad sidebar prunes on appear too, but this covers
    // iPhone and CarPlay where that view never instantiates.
    GlobalSettings.shared.pruneStarredItems(
      validPresetIDs: Set(presets.map { $0.id.uuidString }))

    // Remove cached thumbnail
    removeThumbnail(for: preset.id)

    if wasCurrentPreset {
      Logger.presets.debug("PresetManager: Deleted current preset, switching to default/next")

      // Find next available CUSTOM preset
      if let nextCustomPreset = presets.first(where: { !$0.isDefault }) {
        do {
          Logger.presets.debug(
            "PresetManager: Applying next custom preset '\(nextCustomPreset.name)'")
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
            Logger.presets.debug(
              "PresetManager: No other custom presets. Updating default and setting current preset to nil."
            )
            try applyPreset(updatedDefaultPreset)
          } catch {
            handleError(error)
          }

        } else {
          Logger.presets.debug(
            "PresetManager: No default or custom presets to switch too after deletion")
        }
      }
    }

    savePresets()
    Logger.presets.debug("PresetManager: --- End Delete Preset ---")
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

    // Skip while the mixer doesn't reflect the preset (solo, preview, or none
    // applied yet). Preview forces the previewed sound to volume 1.0, which must
    // not bleed into the saved preset.
    if AudioManager.shared.soloModeSound != nil || AudioManager.shared.previewModeSound != nil
      || !presetStatesApplied
    {
      return
    }

    guard let preset = currentPreset else { return }

    let (newStates, currentSoundOrder) = generateUpdatedPresetData(for: preset)
    updatePresetIfChanged(
      preset: preset, newStates: newStates, currentSoundOrder: currentSoundOrder
    )
  }

  /// First N presets, used for artwork prefetching.
  func getRecentPresets(limit: Int = 5) -> [Preset] {
    return Array(presets.prefix(limit))
  }

  private func generateUpdatedPresetData(for preset: Preset) -> ([PresetState], [String]) {
    let newStates: [PresetState]
    if preset.isDefault {
      // The default preset tracks every available sound (matching
      // updateCurrentPresetBeforeSave), so a freshly imported sound the user
      // selects on the default grid is recorded and survives relaunch.
      newStates = AudioManager.shared.sounds.map { sound in
        PresetState(
          fileName: sound.fileName,
          isSelected: sound.isSelected,
          volume: sound.volume
        )
      }
    } else {
      let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
      newStates = AudioManager.shared.sounds
        .filter { presetSoundFileNames.contains($0.fileName) }
        .map { sound in
          PresetState(
            fileName: sound.fileName,
            isSelected: sound.isSelected,
            volume: sound.volume
          )
        }
    }

    // Preserve the preset's existing sound order, not the global customOrder
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
  func applyPreset(_ preset: Preset, isInitialLoad: Bool = false, forceReapply: Bool = false) throws
  {
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

  }

  /// Remove deleted custom sounds from all presets
  @MainActor
  func cleanupDeletedCustomSounds() {
    Logger.presets.debug("PresetManager: Cleaning up deleted custom sounds from presets")

    // getAllCustomSounds() returns [] both for genuinely-empty and for a
    // transient fetch/container failure. If no customs are visible yet presets
    // still reference some, that's almost certainly a load failure this launch,
    // not a deletion — bail rather than strip every custom state irreversibly.
    let customRows = CustomSoundManager.shared.getAllCustomSounds()
    let presetsReferenceCustoms = presets.contains { preset in
      preset.soundStates.contains { state in
        !AudioManager.shared.sounds.contains { $0.fileName == state.fileName }
      }
    }
    if customRows.isEmpty && presetsReferenceCustoms {
      Logger.presets.debug(
        "PresetManager: Skipping cleanup - no custom sounds available but presets reference customs (likely a transient load failure)"
      )
      return
    }

    // Valid = loaded sounds UNION the SwiftData rows, so a row that exists but
    // failed to load as a Sound this launch is still kept.
    let validSoundFileNames = Set(AudioManager.shared.sounds.map(\.fileName))
      .union(customRows.map(\.fileName))

    // Update each preset to remove invalid sound states
    var didChange = false
    for (index, preset) in presets.enumerated() {
      let validSoundStates = preset.soundStates.filter { soundState in
        validSoundFileNames.contains(soundState.fileName)
      }

      // Only update if there were changes
      if validSoundStates.count != preset.soundStates.count {
        var updatedPreset = preset
        updatedPreset.soundStates = validSoundStates
        presets[index] = updatedPreset
        didChange = true

        // Update current preset if needed
        if currentPreset?.id == preset.id {
          currentPreset = updatedPreset
        }

        Logger.presets.debug(
          "PresetManager: Removed \(preset.soundStates.count - validSoundStates.count) deleted sounds from preset '\(preset.name)'"
        )
      }
    }

    if didChange {
      savePresets()
    }
  }

  @MainActor
  func updateCurrentPresetSoundOrder(from source: IndexSet, to destination: Int) {
    guard let preset = currentPreset else {
      Logger.presets.debug("PresetManager: No current preset to update sound order")
      return
    }

    Logger.presets.debug("PresetManager: Updating sound order for preset '\(preset.name)'")
    Logger.presets.debug("  - Moving from indices: \(source) to destination: \(destination)")

    // Get the current order of sounds in the preset
    var soundOrder = preset.soundOrder ?? preset.soundStates.map(\.fileName)

    // Filter to only include sounds that are actually in the preset
    let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
    soundOrder = soundOrder.filter { presetSoundFileNames.contains($0) }

    // Debug: Print the sound being moved
    for index in source {
      if index < soundOrder.count {
        Logger.presets.debug("  - Moving sound: '\(soundOrder[index])' from index \(index)")
      } else {
        Logger.presets.debug(
          "  - WARNING: Index \(index) out of bounds for soundOrder count \(soundOrder.count)")
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

      Logger.presets.debug("PresetManager: Updated sound order for preset '\(preset.name)'")
      Logger.presets.debug("  - New order: \(soundOrder)")
    }
  }

  @MainActor
  func updateCurrentPresetWithOrder(_ newOrder: [String]) {
    guard let preset = currentPreset else {
      Logger.presets.debug("PresetManager: No current preset to update sound order")
      return
    }

    Logger.presets.debug("PresetManager: Updating sound order for preset '\(preset.name)'")
    Logger.presets.debug("  - New order: \(newOrder)")

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

      Logger.presets.debug("PresetManager: Successfully updated sound order")

      // Verify the update
      if let verifyPreset = presets.first(where: { $0.id == preset.id }) {
        Logger.presets.debug(
          "PresetManager: Verified saved order: \(verifyPreset.soundOrder ?? [])")
      }
    } else {
      Logger.presets.error("PresetManager: Failed to find preset in array!")
    }
  }
}

// MARK: - Application Helpers

extension PresetManager {
  @MainActor func handleAlreadyActivePreset(_ preset: Preset) {
    Logger.presets.debug(
      "PresetManager: Preset already active, but still updating Now Playing info")
    Logger.presets.debug(
      "PresetManager: Artwork ID: \(preset.artworkId != nil ? "\(preset.artworkId!)" : "None")")
    AudioManager.shared.updateNowPlayingInfoForPreset(
      preset: preset,
      presetName: preset.activeTitle,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId
    )
  }

  @MainActor func preparePresetApplication(_ preset: Preset) {
    currentPreset = preset
    // The mixer no longer matches the (now-current) preset until executePreset-
    // Application's async applySoundStates runs. Clear the flag so a debounced
    // updateCurrentPresetState / pre-save landing in that window can't write the
    // OLD preset's mixer state into the new one. applySoundStates sets it back.
    presetStatesApplied = false
    PresetStorage.saveLastActivePresetID(preset.id)

    // Pre-cache artwork for instant display
    Task {
      await PresetArtworkManager.shared.preCacheArtwork(for: preset)
    }

    Logger.presets.debug(
      "PresetManager: Updating Now Playing with artwork ID: \(preset.artworkId != nil ? "\(preset.artworkId!)" : "None")"
    )
    AudioManager.shared.updateNowPlayingInfoForPreset(
      preset: preset,
      presetName: preset.activeTitle,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId
    )
  }

  func executePresetApplication(preset: Preset, isInitialLoad: Bool) {
    // The default grid hides preset-use-only sounds, so never activate one
    // from the default preset — a stale selection (e.g. marked preset-only
    // while a custom preset was current) would play with no tile to stop it.
    let targetStates: [PresetState]
    if preset.isDefault {
      targetStates = preset.soundStates.map { state in
        guard state.isSelected,
          let sound = AudioManager.shared.sounds.first(where: { $0.fileName == state.fileName }),
          sound.isPresetUseOnly
        else { return state }
        Logger.presets.debug(
          "PresetManager: Dropping preset-use-only '\(state.fileName)' from default preset")
        return PresetState(fileName: state.fileName, isSelected: false, volume: state.volume)
      }
    } else {
      targetStates = preset.soundStates
    }
    let wasPlaying = AudioManager.shared.isGloballyPlaying

    Task { @MainActor in
      // A solo sound owns playback (e.g. restored at launch). Don't let preset
      // application start/stop sounds underneath it — the preset is already
      // recorded as current (preparePresetApplication) for when solo is left.
      // Applying sound states here would auto-start the preset's sounds via
      // the isSelected didSet while the solo sound is playing.
      guard AudioManager.shared.soloModeSound == nil else {
        prefetchNearbyAnimatedArtwork(currentPreset: preset)
        return
      }

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

      // Spatial sessions are bound to the mix they started on; switching
      // presets ends them.
      if SpatialSessionManager.shared.isActive {
        SpatialSessionManager.shared.setMode(.off)
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
      let customPresets =
        presets
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

      Logger.presets.debug(
        "PresetManager: Prefetching \(odrIds.count) animated artwork resources for nearby presets")

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
    Logger.presets.error(
      "PresetManager: Error occurred: \(error.localizedDescription, privacy: .public)")
    setError(error)
  }

  func updateCustomPresetStatus() {
    setHasCustomPresets(presets.contains { !$0.isDefault })
  }

  func createDefaultPreset() -> Preset {
    Logger.presets.debug("PresetManager: Creating new default preset")
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

  /// One multi-line summary of a preset (name/ID/default + active sounds).
  private func presetSummary(_ preset: Preset) -> String {
    var lines = [
      "  - Name: '\(preset.name)'",
      "  - ID: \(preset.id)",
      "  - Is Default: \(preset.isDefault)",
    ]
    let activeStates = preset.soundStates.filter { $0.isSelected }
    if !activeStates.isEmpty {
      lines.append("  - Active Sounds:")
      lines += activeStates.map { "    * \($0.fileName) (Volume: \($0.volume))" }
    }
    return lines.joined(separator: "\n")
  }

  func logPresetState(_ preset: Preset) {
    Logger.presets.debug("\(self.presetSummary(preset))")
  }

  func logPresetApplication(_ preset: Preset) {
    Logger.presets.debug(
      "PresetManager: Applying preset '\(preset.name)':\n\(self.presetSummary(preset))")
  }

  @MainActor
  func applySoundStates(_ targetStates: [PresetState]) {
    // Suppress music-exclusivity enforcement while the preset restores its own
    // selection set; we sanitize once at the end instead.
    AudioManager.shared.isApplyingPresetStates = true
    defer { AudioManager.shared.isApplyingPresetStates = false }

    let presetSoundFileNames = Set(targetStates.map(\.fileName))

    // Leaving solo mode: a solo sound that's in the preset keeps playing
    // without a restart; one that isn't must stop.
    if let soloSound = AudioManager.shared.soloModeSound {
      if !presetSoundFileNames.contains(soloSound.fileName) {
        soloSound.isSelected = false
        soloSound.pause()
      }
      AudioManager.shared.exitSoloModeWithoutResuming()
    }

    // Disable sounds that are not in this preset
    for sound in AudioManager.shared.sounds {
      if !presetSoundFileNames.contains(sound.fileName), sound.isSelected {
        Logger.presets.debug("  - Disabling '\(sound.fileName)' (not in preset)")
        sound.isSelected = false
      }
    }

    // Apply the preset's states
    for state in targetStates {
      if let sound = AudioManager.shared.sounds.first(where: { $0.fileName == state.fileName }) {
        let selectionChanged = sound.isSelected != state.isSelected
        let volumeChanged = sound.volume != state.volume

        if selectionChanged || volumeChanged {
          var changes: [String] = []
          if selectionChanged {
            changes.append("selection \(sound.isSelected) -> \(state.isSelected)")
          }
          if volumeChanged { changes.append("volume \(sound.volume) -> \(state.volume)") }
          Logger.presets.debug(
            "  - Configuring '\(sound.fileName)': \(changes.joined(separator: ", "))")

          sound.isSelected = state.isSelected
          sound.volume = state.volume
        }
      }
    }

    // Enforce one music sound for legacy/imported presets that may carry more
    // than one selected music sound. Keep the last one in the preset's order.
    let selectedMusic = AudioManager.shared.sounds.filter { $0.isSelected && $0.isMusic }
    if selectedMusic.count > 1 {
      let keep = targetStates.last { state in
        selectedMusic.contains { $0.fileName == state.fileName }
      }?.fileName
      for sound in selectedMusic where sound.fileName != keep {
        Logger.presets.debug("  - Dropping extra music '\(sound.fileName)' (one music per preset)")
        sound.isSelected = false
      }
    }

    presetStatesApplied = true
  }
}

// MARK: - Persistence

extension PresetManager {
  @MainActor
  func loadPresets() async {
    Logger.presets.debug("PresetManager: --- Begin Loading Presets ---")
    setLoading(true)

    do {
      // Load or create default preset
      var defaultPreset = PresetStorage.loadDefaultPreset() ?? createDefaultPreset()
      // The default preset takes no theme overrides (its sheet doesn't offer
      // them); strip any saved before this rule so they can't apply invisibly.
      if defaultPreset.accentColorName != nil || defaultPreset.viewMode != nil
        || defaultPreset.backgroundBlurRadius != nil
      {
        defaultPreset.accentColorName = nil
        defaultPreset.viewMode = nil
        defaultPreset.backgroundBlurRadius = nil
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
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

      // Migrate legacy blur radii to the on/off model
      migratePresetBlurValues()

      // Ensure all custom presets have order values
      ensurePresetOrder()

      updateCustomPresetStatus()

      // Load last active preset or default
      if let lastID = PresetStorage.loadLastActivePresetID() {
        Logger.presets.debug("PresetManager: Found last active preset ID: \(lastID)")
        if let lastPreset = presets.first(where: { $0.id == lastID }) {
          Logger.presets.debug("PresetManager: Found matching preset: '\(lastPreset.name)'")
          Logger.presets.debug(
            "PresetManager: Loading last active preset:\n\(self.presetSummary(lastPreset))")
          try applyPreset(lastPreset, isInitialLoad: true)
          Logger.presets.debug(
            "PresetManager: Successfully applied last active preset '\(lastPreset.name)'")
        } else {
          Logger.presets.debug(
            "PresetManager: Last active preset ID \(lastID) not found in loaded presets")
          Logger.presets.debug(
            "PresetManager: Available presets: \(self.presets.map { "\($0.name) (\($0.id))" })")
          Logger.presets.debug("PresetManager: Falling back to default preset")
          try applyPreset(presets[0], isInitialLoad: true)
        }
      } else {
        Logger.presets.debug("PresetManager: No last active preset ID found, applying default")
        try applyPreset(presets[0], isInitialLoad: true)
      }
    } catch {
      handleError(error)
    }

    setLoading(false)
    setInitialLoad(false)
    Logger.presets.debug("PresetManager: --- End Loading Presets ---")
  }

  @MainActor
  func savePresets() {
    // Skip saving during initialization - nothing has actually changed
    guard !isInitializing else {
      Logger.presets.debug("PresetManager: Skipping save during initialization")
      return
    }

    Logger.presets.debug("PresetManager: --- Begin Saving Presets ---")

    updateCurrentPresetBeforeSave()
    performActualSave()

    Logger.presets.debug("PresetManager: --- End Saving Presets ---")
  }

  @MainActor
  private func updateCurrentPresetBeforeSave() {
    // Skip while the mixer doesn't reflect the preset (solo, preview, or none
    // applied yet). Preview forces the previewed sound to volume 1.0.
    guard AudioManager.shared.soloModeSound == nil, AudioManager.shared.previewModeSound == nil,
      presetStatesApplied
    else { return }

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

      Logger.presets.debug("Saving current preset state for '\(updatedPreset.name)':")
      Logger.presets.debug("  - Active sounds:")
      updatedPreset.soundStates
        .filter { $0.isSelected }
        .forEach { state in
          Logger.presets.debug("    * \(state.fileName) (Volume: \(state.volume))")
        }
    }
  }

  @MainActor
  private func performActualSave() {
    let defaultPreset = presets.first { $0.isDefault }
    let customPresets = presets.filter { !$0.isDefault }

    // Write synchronously on the main actor. Encoding a handful of presets into
    // UserDefaults is cheap, and the previous Task.detached produced unordered
    // writes where two rapid saves could land the older snapshot last.
    if let defaultPreset = defaultPreset {
      PresetStorage.saveDefaultPreset(defaultPreset)
    }
    PresetStorage.saveCustomPresets(customPresets)

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
          Logger.presets.debug(
            "PresetManager: Migrating sound name in preset '\(preset.name)': '\(soundState.fileName)' -> '\(migratedFileName)'"
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
      Logger.presets.debug("PresetManager: Preset migration completed, saving updated presets")

      // Save the migrated presets immediately
      let defaultPreset = migratedPresets.first { $0.isDefault }
      let customPresets = migratedPresets.filter { !$0.isDefault }

      if let defaultPreset = defaultPreset {
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
      PresetStorage.saveCustomPresets(customPresets)
    }
  }

  /// Migrates per-preset blur overrides from the old radius choices (e.g.
  /// "High" 15) to the on/off model: any radius > 0 becomes the single
  /// `defaultBackgroundBlurRadius`, 0 stays off, nil keeps following the app
  /// setting.
  private func migratePresetBlurValues() {
    var migratedPresets = [Preset]()
    var hasMigrations = false

    for preset in presets {
      if let radius = preset.backgroundBlurRadius,
        radius != 0, radius != defaultBackgroundBlurRadius
      {
        var migratedPreset = preset
        migratedPreset.backgroundBlurRadius = defaultBackgroundBlurRadius
        migratedPresets.append(migratedPreset)
        hasMigrations = true
        Logger.presets.debug(
          "PresetManager: Migrating blur in preset '\(preset.name)': \(radius) -> \(defaultBackgroundBlurRadius)"
        )
      } else {
        migratedPresets.append(preset)
      }
    }

    if hasMigrations {
      setPresets(migratedPresets)
      Logger.presets.debug("PresetManager: Blur migration completed, saving updated presets")

      if let defaultPreset = migratedPresets.first(where: { $0.isDefault }) {
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
      PresetStorage.saveCustomPresets(migratedPresets.filter { !$0.isDefault })
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
          Logger.presets.debug("PresetManager: Found duplicate order value: \(order)")
          break
        }
        orderValues.insert(order)
      }
    }

    // Check if any custom preset is missing order or has duplicates
    let hasUnorderedPresets = customPresets.contains { $0.order == nil } || hasDuplicates

    if hasUnorderedPresets {
      Logger.presets.debug("PresetManager: Reassigning order values to all custom presets")

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
        Logger.presets.debug(
          "PresetManager: Updating order for '\(preset.name)' from \(preset.order ?? -1) to \(index)"
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
  /// Cache a small thumbnail for quick access. Pass `force: true` after an
  /// artwork edit to regenerate an already-cached thumbnail.
  @MainActor
  func cacheThumbnail(for preset: Preset, force: Bool = false) async {
    #if os(iOS)
      // Check if thumbnail is already cached
      let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"
      let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
      if !force, userDefaults.data(forKey: thumbnailKey) != nil {
        return  // Already cached
      }

      // Source image: static artwork if present, else the animated artwork's
      // preview — so presets with only animated artwork still get a CarPlay
      // thumbnail (matching the mixer / Now Playing / library picker).
      guard let fullImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
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
        Logger.presets.debug("PresetManager: Cached thumbnail for preset '\(preset.displayName)'")
        NotificationCenter.default.post(name: .presetThumbnailUpdated, object: preset.id)
      }
    #endif
  }

  /// Cache thumbnails for all presets
  @MainActor
  func cacheAllThumbnails() async {
    // Don't cache if we're still loading
    guard !isLoading else {
      Logger.presets.debug("PresetManager: Skipping thumbnail cache - still loading")
      return
    }

    for preset in presets {
      await cacheThumbnail(for: preset)
    }
  }

  /// Remove cached thumbnail when a preset is deleted or its artwork removed
  func removeThumbnail(for presetId: UUID) {
    let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
    userDefaults.removeObject(forKey: "preset_thumb_\(presetId.uuidString)")
    NotificationCenter.default.post(name: .presetThumbnailUpdated, object: presetId)
  }
}

extension Notification.Name {
  /// Posted when a preset's CarPlay thumbnail is regenerated or removed, so
  /// connected CarPlay list templates can refresh their artwork.
  static let presetThumbnailUpdated = Notification.Name("presetThumbnailUpdated")
}
