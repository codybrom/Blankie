//
//  PresetManager.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import CoreSpotlight
import Foundation
import Observation
import SwiftUI
import os

@Observable
class PresetManager {
  @ObservationIgnored private var isInitializing = true
  /// Sorted, order-independent signature of the names last published to Siri and
  /// Spotlight, so repeat refreshes no-op until that set changes. Per-process.
  @ObservationIgnored private var lastDiscoverableEntitiesSignature: String?
  @ObservationIgnored private var spotlightDonationTask: Task<Void, Never>?
  /// Only the latest thumbnail request for a preset may commit its result.
  @ObservationIgnored private var thumbnailRequests: [UUID: UUID] = [:]
  static let shared = PresetManager()

  private(set) var presets: [Preset] = []
  var currentPreset: Preset? {
    didSet {
      AudioManager.shared.updateNowPlayingInfoForPreset(
        preset: currentPreset,
        presetName: currentPreset?.activeTitle,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId
      )
      // Next/previous cycles favorites relative to the current preset, so
      // recompute on every preset change, including the restore at launch.
      AudioManager.shared.updateNextPreviousCommandState()
    }
  }

  private(set) var hasCustomPresets: Bool = false
  private(set) var isLoading: Bool = true
  /// Launch couldn't restore the last active preset (deleted, or it failed to
  /// apply) and fell back to the default, so the UI opens on the Library.
  private(set) var lastPresetRestoreFailed = false
  private(set) var error: Error?

  /// The preset whose theme (accent, blur, view mode) drives the UI. Nil in single sound
  /// (which keeps `currentPreset` for restore) and Quick Mix. Views reading this
  /// must also observe `AudioManager` to update when those modes change.
  @MainActor
  var themingPreset: Preset? {
    // Derived from activeItem so this agrees with currentFavoriteToken.
    switch AudioManager.shared.activeItem {
    case .preset, .allSounds:
      return currentPreset
    case .single, .quickMix, .none:
      return nil
    }
  }

  /// The active preset holds none of the loaded sounds, so only the editor
  /// can give it something to play. Never true for the default preset.
  @MainActor
  var currentPresetHasNoSounds: Bool {
    guard let preset = themingPreset, !preset.isDefault else { return false }
    return !AudioManager.shared.sounds.contains { sound in
      preset.soundStates.contains { $0.fileName == sound.fileName }
    }
  }

  /// Watches the sounds array so an imported or deleted sound re-checks preset
  /// divergence. Per-sound changes arrive via `AudioManager.soundDidChange()`.
  @ObservationIgnored private var soundsObservation: Task<Void, Never>?
  @ObservationIgnored private var isInitialLoad = true

  /// Set by applySoundStates. Until then the mixer may not match the preset.
  @ObservationIgnored var presetStatesApplied = false

  // In-flight prefetch for nearby preset animated artwork, cancelled when the
  // current preset changes so stale prefetches don't compete with the new one.
  @ObservationIgnored private var nearbyArtworkPrefetchTask: Task<Void, Never>?

  private init() {
    Logger.presets.debug("PresetManager: --- Begin Initialization ---")

    soundsObservation = Task { @MainActor [weak self] in
      for await _ in Observations({ AudioManager.shared.sounds.count }) {
        self?.updateCurrentPresetState()
      }
    }

    // Presets load in initializePresetManager(), after custom sounds.
    Logger.presets.debug("PresetManager: --- End Initialization (deferred preset loading) ---")
  }

  /// Loads presets. Call after AudioManager has loaded all sounds, including custom ones.
  @MainActor
  func initializePresetManager() async {
    guard isInitializing else {
      Logger.presets.debug("PresetManager: Already initialized, skipping")
      return
    }

    Logger.presets.debug("PresetManager: --- Begin Preset Loading After Sound Setup ---")
    await loadPresets()

    isInitializing = false

    // Deferred so CarPlay thumbnail caching doesn't delay applying the preset.
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
    soundsObservation?.cancel()
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
    updatedPreset.lastModifiedVersion = Bundle.main.appVersion

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

    // Delete the stored PresetArtwork rows too. cleanupAnimatedArtworkFiles only
    // removes the on-disk .mov and preview files.
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

    removeThumbnail(for: preset.id)

    if wasCurrentPreset {
      Logger.presets.debug("PresetManager: Deleted current preset, switching to default/next")

      if let nextCustomPreset = presets.first(where: { !$0.isDefault }) {
        do {
          Logger.presets.debug(
            "PresetManager: Applying next custom preset '\(nextCustomPreset.name)'")
          // Deleting while paused stays paused.
          try applyPreset(nextCustomPreset, autoPlay: AudioManager.shared.isGloballyPlaying)
        } catch {
          handleError(error)
        }
      } else {
        // No other custom presets: the default takes over the deleted preset's mix.
        // It still lists every sound that exists (the default always does), so it
        // applies even when the deleted preset named a sound that's now gone.
        if let defaultPresetIndex = presets.firstIndex(where: { $0.isDefault }) {
          var updatedDefaultPreset = presets[defaultPresetIndex]
          let deletedStates = Dictionary(
            preset.soundStates.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
          let defaultStates = Dictionary(
            updatedDefaultPreset.soundStates.map { ($0.fileName, $0) },
            uniquingKeysWith: { first, _ in first })
          updatedDefaultPreset.soundStates = AudioManager.shared.sounds.map { sound in
            deletedStates[sound.fileName]
              ?? PresetState(
                fileName: sound.fileName, isSelected: false,
                volume: defaultStates[sound.fileName]?.volume ?? sound.volume)
          }
          presets[defaultPresetIndex] = updatedDefaultPreset

          do {
            Logger.presets.debug(
              "PresetManager: No other custom presets. Updating default and setting current preset to nil."
            )
            try applyPreset(updatedDefaultPreset, autoPlay: AudioManager.shared.isGloballyPlaying)
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

  /// Custom sounds that deleting `preset` would orphan: members of it that are in
  /// no other custom preset and not currently selected. The default preset holds
  /// every sound, so it counts only through the selection check.
  @MainActor
  func orphanedCustomSounds(ifDeleting preset: Preset) -> [Sound] {
    guard !preset.isDefault else { return [] }
    let audio = AudioManager.shared
    let presetMembers = Set(preset.soundStates.map(\.fileName))
    let otherCustomMembers = Set(
      presets
        .filter { !$0.isDefault && $0.id != preset.id }
        .flatMap { $0.soundStates.map(\.fileName) })
    // The default's live selection when it's active, otherwise its saved one.
    // The deleted preset's live selection doesn't count, or its playing sounds
    // would be spared.
    let defaultIsActive = currentPreset == nil || (currentPreset?.isDefault ?? false)
    let selectedOnDefault: Set<String>
    if defaultIsActive {
      selectedOnDefault = Set(audio.sounds.filter(\.isSelected).map(\.fileName))
    } else {
      selectedOnDefault = Set(
        presets.first { $0.isDefault }?.soundStates.filter(\.isSelected).map(\.fileName) ?? [])
    }
    return audio.sounds.filter { sound in
      sound.isCustom
        && presetMembers.contains(sound.fileName)
        && !otherCustomMembers.contains(sound.fileName)
        && !selectedOnDefault.contains(sound.fileName)
        && audio.singleSound?.id != sound.id
        && audio.previewModeSound?.id != sound.id
    }
  }

  /// Deletes `preset`, and when asked, every custom sound it leaves orphaned.
  /// Orphans are captured before the preset is removed so the membership basis
  /// is still intact, then deleted through the normal custom-sound path.
  @MainActor
  func deletePreset(_ preset: Preset, alsoDeleteOrphanedSounds: Bool) {
    let orphans = alsoDeleteOrphanedSounds ? orphanedCustomSounds(ifDeleting: preset) : []
    deletePreset(preset)
    for sound in orphans {
      guard let id = sound.customSoundDataID,
        let data = CustomSoundManager.shared.getCustomSound(by: id)
      else { continue }
      _ = CustomSoundManager.shared.deleteCustomSound(data)
    }
  }

  /// Adds or removes `fileName` from a custom preset, live. Removing it from the
  /// active preset stops the sound if it's currently playing (matching the Edit
  /// Preset screen). No-op for the default preset, which always holds everything.
  @MainActor
  func setSound(_ fileName: String, member: Bool, ofPreset presetID: UUID, volume: Float) {
    guard let index = presets.firstIndex(where: { $0.id == presetID }), !presets[index].isDefault
    else { return }
    var preset = presets[index]
    let alreadyMember = preset.soundStates.contains { $0.fileName == fileName }
    if member, !alreadyMember {
      preset.soundStates.append(PresetState(fileName: fileName, isSelected: false, volume: volume))
    } else if !member, alreadyMember {
      preset.soundStates.removeAll { $0.fileName == fileName }
      if currentPreset?.id == presetID,
        let sound = AudioManager.shared.sounds.first(where: { $0.fileName == fileName }),
        sound.isSelected
      {
        sound.isSelected = false
      }
    } else {
      return
    }
    preset.lastModifiedVersion = Bundle.main.appVersion
    presets[index] = preset
    if currentPreset?.id == presetID {
      currentPreset = preset
    }
    savePresets()
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

    // Skip while the mixer doesn't reflect the preset (single sound, preview, or none
    // applied yet). Preview forces the previewed sound to volume 1.0, which must
    // not bleed into the saved preset.
    if AudioManager.shared.singleSound != nil || AudioManager.shared.previewModeSound != nil
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
      newStates = AudioManager.shared.sounds.map { $0.captureState() }
    } else {
      let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
      newStates = AudioManager.shared.sounds
        .filter { presetSoundFileNames.contains($0.fileName) }
        .map { $0.captureState() }
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
      updatedPreset.lastModifiedVersion = Bundle.main.appVersion

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

  /// Starts a preset from Siri, a widget or CarPlay. Leaves single sound and Quick Mix
  /// first, since an application skips single sound and never exits Quick Mix itself.
  /// An application plays the new mix, so only a current preset needs a play.
  @MainActor
  func playPreset(_ preset: Preset) throws {
    // Validate before leaving Quick Mix, which drops the earlier mix. An empty
    // preset opens in the app, but Siri, widgets and CarPlay can't play it.
    guard preset.validate(), !preset.soundStates.isEmpty else {
      throw PresetError.invalidPreset
    }
    AudioManager.shared.leaveTransientModes()
    if try !applyPreset(preset) {
      AudioManager.shared.setGlobalPlaybackState(true)
    }
  }

  @MainActor
  /// `autoPlay: false` applies the mix without starting playback (remote
  /// next/previous while paused). Returns false when the preset was already
  /// active and nothing was applied. Callers that want playback start it only
  /// then, since an application starts playback itself once the new mix is in.
  @discardableResult
  func applyPreset(
    _ preset: Preset, isInitialLoad: Bool = false, forceReapply: Bool = false,
    autoPlay: Bool = true
  ) throws -> Bool {
    logPresetApplication(preset)

    guard preset.validate() else {
      throw PresetError.invalidPreset
    }

    // A preset command ends a sound-editor preview first. Resume the mix only
    // when it stays, because an application replaces it.
    if preset.id == currentPreset?.id, !isInitialLoad, !forceReapply {
      AudioManager.shared.exitPreviewMode()
      handleAlreadyActivePreset(preset)
      return false
    }
    AudioManager.shared.exitPreviewMode(resuming: false)

    preparePresetApplication(preset)
    executePresetApplication(preset: preset, isInitialLoad: isInitialLoad, autoPlay: autoPlay)
    return true
  }

  /// Outcome of deciding which custom-sound states to keep. Pure and `Equatable`
  /// so the data-loss-critical guard can be unit tested without the singletons.
  enum CustomSoundCleanupDecision: Equatable {
    /// No custom rows are visible but presets still reference customs, most
    /// likely a transient load failure, so keep everything.
    case skipTransient
    /// The per-preset filtered states, in the same order as the input.
    case filtered([[PresetState]])
  }

  /// Decision core for `cleanupDeletedCustomSounds`, kept free of singletons so
  /// the transient-failure guard and the valid set are testable.
  static func customSoundCleanupDecision(
    presetStates: [[PresetState]],
    loadedSoundFileNames: Set<String>,
    customRowFileNames: Set<String>
  ) -> CustomSoundCleanupDecision {
    // getAllCustomSounds() returns [] both when empty and on a transient fetch
    // failure. Presets that still reference customs mean a failure, so keep all.
    let presetsReferenceCustoms = presetStates.contains { states in
      states.contains { !loadedSoundFileNames.contains($0.fileName) }
    }
    if customRowFileNames.isEmpty && presetsReferenceCustoms {
      return .skipTransient
    }

    // Valid is loaded sounds plus SwiftData rows, so a row that failed to load
    // as a Sound this launch is still kept.
    let valid = loadedSoundFileNames.union(customRowFileNames)
    return .filtered(presetStates.map { states in states.filter { valid.contains($0.fileName) } })
  }

  /// Remove deleted custom sounds from all presets
  @MainActor
  func cleanupDeletedCustomSounds() {
    Logger.presets.debug("PresetManager: Cleaning up deleted custom sounds from presets")

    let customRows = CustomSoundManager.shared.getAllCustomSounds()
    let decision = Self.customSoundCleanupDecision(
      presetStates: presets.map(\.soundStates),
      loadedSoundFileNames: Set(AudioManager.shared.sounds.map(\.fileName)),
      // Audio still on disk counts too: a row can vanish in a store rebuild while
      // its file survives, and pruning here is irreversible.
      customRowFileNames: Set(customRows.map(\.fileName))
        .union(CustomSoundManager.shared.customAudioFileNamesOnDisk())
    )
    guard case .filtered(let filteredStates) = decision else {
      Logger.presets.debug(
        "PresetManager: Skipping cleanup - no custom sounds available but presets reference customs (likely a transient load failure)"
      )
      return
    }

    var didChange = false
    for (index, validSoundStates) in filteredStates.enumerated() {
      let preset = presets[index]

      if validSoundStates.count != preset.soundStates.count {
        var updatedPreset = preset
        updatedPreset.soundStates = validSoundStates
        presets[index] = updatedPreset
        didChange = true

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

    var soundOrder = preset.soundOrder ?? preset.soundStates.map(\.fileName)

    let presetSoundFileNames = Set(preset.soundStates.map(\.fileName))
    soundOrder = soundOrder.filter { presetSoundFileNames.contains($0) }

    for index in source {
      if index < soundOrder.count {
        Logger.presets.debug("  - Moving sound: '\(soundOrder[index])' from index \(index)")
      } else {
        Logger.presets.debug(
          "  - WARNING: Index \(index) out of bounds for soundOrder count \(soundOrder.count)")
      }
    }

    soundOrder.move(fromOffsets: source, toOffset: destination)

    var updatedPreset = preset
    updatedPreset.soundOrder = soundOrder
    updatedPreset.lastModifiedVersion = Bundle.main.appVersion

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

    var updatedPreset = preset
    updatedPreset.soundOrder = newOrder
    updatedPreset.lastModifiedVersion = Bundle.main.appVersion

    if let index = presets.firstIndex(where: { $0.id == preset.id }) {
      presets[index] = updatedPreset
      currentPreset = updatedPreset
      savePresets()

      Logger.presets.debug("PresetManager: Successfully updated sound order")

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
    // Persist an edit still waiting on the 100 ms coalesced refresh into the
    // outgoing preset. Once the switch lands, that refresh skips or targets the new one.
    updateCurrentPresetState()
    currentPreset = preset
    // The mixer doesn't match the new preset until applySoundStates runs and
    // sets this back, so a debounced save in between can't write the old mix.
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

  func executePresetApplication(preset: Preset, isInitialLoad: Bool, autoPlay: Bool = true) {
    // The default preset hides preset-use-only sounds, so never activate one
    // there. A stale selection would play with no tile to stop it.
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
      // A single sound owns playback (for example, restored at launch). The preset
      // is already current for when single sound ends, so don't apply its states now.
      guard AudioManager.shared.singleSound == nil else {
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

      let shouldAutoPlay = autoPlay && (!isInitialLoad || GlobalSettings.shared.autoPlayOnLaunch)
      if shouldAutoPlay, targetStates.contains(where: { $0.isSelected }) {
        AudioManager.shared.setGlobalPlaybackState(true)
      }

      // Spatial sessions are bound to the mix they started on, so switching
      // presets ends them.
      if SpatialSessionManager.shared.isActive {
        SpatialSessionManager.shared.setMode(.off)
      }

      // Prefetch animated artwork for nearby presets so they're available on lock screen
      prefetchNearbyAnimatedArtwork(currentPreset: preset)
    }
  }

  /// Prefetches animated artwork for the next and previous presets so it's ready
  /// when switching from the lock screen.
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
        // Prefetch the variant this device will actually use, so iPad warms the
        // square packs (not the portrait ones it never plays).
        await BackgroundResourceManager.shared.preload(
          odrIds.map { BackgroundResourceManager.preferredPackID(for: $0) })
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
    let currentVersion = Bundle.main.appVersion
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
    // selection set. We sanitize once at the end instead.
    AudioManager.shared.isApplyingPresetStates = true
    defer { AudioManager.shared.isApplyingPresetStates = false }

    let presetSoundFileNames = Set(targetStates.map(\.fileName))

    // Leaving single-sound mode: a single sound that's in the preset keeps playing
    // without a restart. One that isn't must stop.
    if let singleSound = AudioManager.shared.singleSound {
      if !presetSoundFileNames.contains(singleSound.fileName) {
        singleSound.isSelected = false
        singleSound.pause()
      }
      AudioManager.shared.exitSingleSoundWithoutResuming()
    }

    // Disable sounds that are not in this preset
    for sound in AudioManager.shared.sounds {
      if !presetSoundFileNames.contains(sound.fileName), sound.isSelected {
        Logger.presets.debug("  - Disabling '\(sound.fileName)' (not in preset)")
        sound.isSelected = false
      }
    }

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
      var defaultPreset = PresetStorage.loadDefaultPreset() ?? createDefaultPreset()
      // The default preset takes no theme overrides (its sheet doesn't offer
      // them), so strip any saved ones.
      if defaultPreset.accentColorName != nil || defaultPreset.viewMode != nil
        || defaultPreset.backgroundBlurRadius != nil
      {
        defaultPreset.accentColorName = nil
        defaultPreset.viewMode = nil
        defaultPreset.backgroundBlurRadius = nil
        PresetStorage.saveDefaultPreset(defaultPreset)
      }
      setPresets([defaultPreset])

      let customPresets = PresetStorage.loadCustomPresets()
      if !customPresets.isEmpty {
        var allPresets = presets
        allPresets.append(contentsOf: customPresets)
        setPresets(allPresets)
      }

      // Migrate any presets that contain old sound names with file extensions
      migratePresetSoundNames()

      ensurePresetOrder()

      updateCustomPresetStatus()

      // A last active preset that fails validation (say, a sound it uses is
      // gone) falls back to the default.
      let lastID = PresetStorage.loadLastActivePresetID()
      let lastPreset = lastID.flatMap { id in presets.first { $0.id == id } }
      if let lastID, lastPreset == nil {
        Logger.presets.debug(
          "PresetManager: Last active preset ID \(lastID) not found, applying default")
        lastPresetRestoreFailed = true
      }
      do {
        try applyPreset(lastPreset ?? presets[0], isInitialLoad: true)
      } catch  where lastPreset != nil {
        Logger.presets.error(
          "PresetManager: Last active preset failed to apply (\(error, privacy: .public)); applying default"
        )
        lastPresetRestoreFailed = true
        try applyPreset(presets[0], isInitialLoad: true)
      }
    } catch {
      handleError(error)
      lastPresetRestoreFailed = true
      // Never finish loading without a preset: show the default even if its mix
      // couldn't be applied.
      if currentPreset == nil, let defaultPreset = presets.first {
        setCurrentPreset(defaultPreset)
      }
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
    refreshDiscoverableEntitiesIfNeeded()
    // Names, accents, and membership feed the widgets. Publish skips identical snapshots.
    AudioManager.shared.republishWidgetCatalog()

    Logger.presets.debug("PresetManager: --- End Saving Presets ---")
  }

  /// Refreshes the Siri vocabulary for `PlayPresetIntent` and `PlaySoundIntent`
  /// and the Spotlight index when the set of names changes. Cheap to call often.
  /// Skipped in the widget extension, which also compiles this file.
  func refreshDiscoverableEntitiesIfNeeded() {
    #if !WIDGET_EXTENSION
      // Deterministic, order-independent signature over exactly what's donated
      // (presets + non-preset-only sounds, matching `donateEntitiesToSpotlight`
      // and `SoundEntityQuery`), so reordering alone doesn't force a refresh.
      let presetPart = presets.map { "\($0.id.uuidString):\($0.name)" }.sorted()
      let soundPart =
        AudioManager.shared.sounds
        .filter { !$0.isPresetUseOnly }
        .map { "\($0.fileName):\($0.localizedTitle)" }
        .sorted()
      let signature = (presetPart + ["~"] + soundPart).joined(separator: "|")
      guard signature != lastDiscoverableEntitiesSignature else { return }
      lastDiscoverableEntitiesSignature = signature
      // App Shortcut parameters are only refreshed on iOS. Spotlight runs on both.
      #if !os(macOS)
        BlankieShortcuts.updateAppShortcutParameters()
      #endif
      donateEntitiesToSpotlight()
    #endif
  }

  #if !WIDGET_EXTENSION
    /// Replaces the named Spotlight indexes with the current presets and the sounds that can play
    /// on their own. Indexing is additive, so each type is deleted first. Failures are non-fatal.
    private func donateEntitiesToSpotlight() {
      let presetEntities = presets.map(PresetEntity.init)
      let soundEntities =
        AudioManager.shared.sounds
        .filter { !$0.isPresetUseOnly }
        .map(SoundEntity.init)
      // Named indexes keyed off the app's own bundle ID (so contributor builds
      // don't collide), not the default index Apple reserves for dev/testing.
      let bundleID = Bundle.main.bundleIdentifier ?? "com.codybrom.blankie"
      // Chain on the previous donation so overlapping refreshes (an archive
      // import posts one per custom sound) can't interleave delete and index.
      let previous = spotlightDonationTask
      spotlightDonationTask = Task {
        await previous?.value
        do {
          let presetIndex = CSSearchableIndex(name: "\(bundleID).presets")
          try await presetIndex.deleteAppEntities(ofType: PresetEntity.self)
          try await presetIndex.indexAppEntities(presetEntities)
          let soundIndex = CSSearchableIndex(name: "\(bundleID).sounds")
          try await soundIndex.deleteAppEntities(ofType: SoundEntity.self)
          try await soundIndex.indexAppEntities(soundEntities)
        } catch {
          Logger.presets.error("Spotlight: entity indexing failed: \(error, privacy: .public)")
          // Forget the signature so the next refresh retries.
          lastDiscoverableEntitiesSignature = nil
        }
      }
    }
  #endif

  @MainActor
  private func updateCurrentPresetBeforeSave() {
    // Skip while the mixer doesn't reflect the preset (single sound, preview, or none
    // applied yet). Preview forces the previewed sound to volume 1.0.
    guard AudioManager.shared.singleSound == nil, AudioManager.shared.previewModeSound == nil,
      presetStatesApplied
    else { return }

    if let currentPreset = currentPreset,
      let index = presets.firstIndex(where: { $0.id == currentPreset.id })
    {
      // Get the preset from the array to preserve any updates (like order)
      var updatedPreset = presets[index]
      // For custom presets, only update sounds that are already in the preset
      if !updatedPreset.isDefault {
        updatedPreset.soundStates = updatedPreset.soundStates.map { existingState in
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
        updatedPreset.soundStates = AudioManager.shared.sounds.map { $0.captureState() }
      }
      updatePresetAtIndex(index, with: updatedPreset)
      setCurrentPreset(updatedPreset)

      let activeCount = updatedPreset.soundStates.filter { $0.isSelected }.count
      Logger.presets.debug(
        "Saving current preset state for '\(updatedPreset.name)' (\(activeCount) active sounds)")
    }
  }

  @MainActor
  private func performActualSave() {
    let defaultPreset = presets.first { $0.isDefault }
    let customPresets = presets.filter { !$0.isDefault }

    // Write synchronously on the main actor so rapid saves land in order.
    // Encoding a handful of presets into UserDefaults is cheap.
    if let defaultPreset = defaultPreset {
      PresetStorage.saveDefaultPreset(defaultPreset)
    }
    PresetStorage.saveCustomPresets(customPresets)

    // Cache thumbnails for quick access
    Task {
      await cacheAllThumbnails()
    }
  }

  /// Strips file extensions from preset sound names saved in the old format.
  private func migratePresetSoundNames() {
    let legacyExtensions = ["mp3", "m4a", "wav", "aiff"]
    var migratedPresets = [Preset]()
    var hasMigrations = false

    for preset in presets {
      var migratedSoundStates = [PresetState]()
      var presetHasMigrations = false

      for soundState in preset.soundStates {
        var migratedFileName = soundState.fileName

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

  /// Ensures all custom presets have unique order values assigned
  @MainActor
  private func ensurePresetOrder() {
    var needsSave = false
    var updatedPresets = presets

    let customPresets = updatedPresets.filter { !$0.isDefault }

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

    let hasUnorderedPresets = customPresets.contains { $0.order == nil } || hasDuplicates

    if hasUnorderedPresets {
      Logger.presets.debug("PresetManager: Reassigning order values to all custom presets")

      // Sort custom presets by current order (if exists) then by name
      let sortedCustomPresets = customPresets.sorted { preset1, preset2 in
        if let order1 = preset1.order, let order2 = preset2.order {
          return order1 < order2
        }
        if preset1.order != nil, preset2.order == nil {
          return true
        }
        if preset1.order == nil, preset2.order != nil {
          return false
        }
        return preset1.name < preset2.name
      }

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
  /// Cache a small CarPlay thumbnail and higher-resolution widget artwork.
  /// Existing small thumbnails are upgraded on the next normal cache pass.
  @MainActor
  @discardableResult
  func cacheThumbnail(
    for preset: Preset, force: Bool = false, reloadingWidgets: Bool = true,
    renderThumbnails: @Sendable (Data) async -> (carPlay: Data?, widget: Data?) =
      PresetManager.renderThumbnailData
  ) async -> Bool {
    let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"
    let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
    let widgetURL = WidgetArtworkCache.fileURL(for: thumbnailKey)
    if !force, userDefaults.data(forKey: thumbnailKey) != nil,
      let widgetURL, FileManager.default.fileExists(atPath: widgetURL.path)
    {
      return false
    }

    let request = UUID()
    thumbnailRequests[preset.id] = request
    defer {
      if thumbnailRequests[preset.id] == request {
        thumbnailRequests.removeValue(forKey: preset.id)
      }
    }

    // Static artwork takes precedence over the animation preview, as in the app.
    guard let fullImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
    else { return false }
    #if canImport(UIKit)
      let sourceData = fullImage.pngData()
    #else
      let sourceData = fullImage.tiffRepresentation
    #endif
    guard let sourceData else { return false }
    let images = await renderThumbnails(sourceData)
    // Loading and rendering both suspend. An edit or removal can invalidate
    // this request in either interval, so never let its old image return afterward.
    guard !Task.isCancelled, thumbnailRequests[preset.id] == request else { return false }
    guard let thumbnailData = images.carPlay, let widgetData = images.widget else { return false }

    // Large artwork stays out of UserDefaults and is readable while locked.
    if let widgetURL {
      do {
        try AppGroupConfiguration.writeProtectionlessFile(widgetData, to: widgetURL)
      } catch {
        Logger.presets.error(
          "PresetManager: Could not cache widget artwork: \(error.localizedDescription)")
      }
    }
    userDefaults.set(thumbnailData, forKey: thumbnailKey)
    Logger.presets.debug("PresetManager: Cached artwork for preset '\(preset.displayName)'")
    NotificationCenter.default.post(name: .presetThumbnailUpdated, object: preset.id)
    if reloadingWidgets {
      WidgetStateStore.artworkDidChange()
    }
    return true
  }

  nonisolated private static func renderThumbnailData(_ sourceData: Data) async -> (
    carPlay: Data?, widget: Data?
  ) {
    await Task.detached(priority: .utility) {
      (
        carPlay: WidgetArtworkCache.jpegThumbnail(from: sourceData, maxPixelSize: 132),
        widget: WidgetArtworkCache.jpegThumbnail(from: sourceData)
      )
    }.value
  }

  /// Cache thumbnails for all presets, reloading widgets once if any were written.
  @MainActor
  func cacheAllThumbnails() async {
    guard !isLoading else {
      Logger.presets.debug("PresetManager: Skipping thumbnail cache - still loading")
      return
    }

    var wroteAny = false
    for preset in presets {
      if await cacheThumbnail(for: preset, reloadingWidgets: false) {
        wroteAny = true
      }
    }
    if wroteAny {
      WidgetStateStore.artworkDidChange()
    }
  }

  /// Remove cached thumbnail when a preset is deleted or its artwork removed
  func removeThumbnail(for presetId: UUID) {
    // Invalidate even when no files exist yet: a first render may be in flight.
    thumbnailRequests.removeValue(forKey: presetId)
    let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard
    let thumbnailKey = "preset_thumb_\(presetId.uuidString)"
    let widgetURL = WidgetArtworkCache.fileURL(for: thumbnailKey)
    let hasWidgetArtwork =
      widgetURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    guard userDefaults.data(forKey: thumbnailKey) != nil || hasWidgetArtwork else { return }
    userDefaults.removeObject(forKey: thumbnailKey)
    if let widgetURL { try? FileManager.default.removeItem(at: widgetURL) }
    NotificationCenter.default.post(name: .presetThumbnailUpdated, object: presetId)
    WidgetStateStore.artworkDidChange()
  }
}

extension Notification.Name {
  /// Posted when a preset's CarPlay thumbnail is regenerated or removed, so
  /// connected CarPlay list templates can refresh their artwork.
  static let presetThumbnailUpdated = Notification.Name("presetThumbnailUpdated")
}
