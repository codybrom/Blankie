//
//  AudioManager+SoundLoading.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import SwiftData
import SwiftUI
import os

// MARK: - Sound Loading

extension AudioManager {
  func loadSounds() {
    Logger.audio.debug("AudioManager: Loading built-in sounds from JSON")

    // Start with an empty array
    sounds = []

    // Load built-in sounds
    loadBuiltInSounds()

    // Load the saved default sound order after built-in sounds are loaded
    // (Custom sounds will update the order when they're loaded)
    if let savedOrder = UserDefaults.shared.stringArray(forKey: "defaultSoundOrder") {
      defaultSoundOrder = savedOrder
      Logger.audio.debug("AudioManager: Loaded default sound order with \(savedOrder.count) sounds")

      // Add any new built-in sounds that aren't in the saved order
      let currentSoundFileNames = Set(sounds.map(\.fileName))
      let savedOrderSet = Set(savedOrder)
      let newSounds = currentSoundFileNames.subtracting(savedOrderSet)

      if !newSounds.isEmpty {
        defaultSoundOrder.append(contentsOf: newSounds)
        UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
        Logger.audio.debug("AudioManager: Added \(newSounds.count) new sounds to default order")
      }
    } else {
      // Initialize with default order (all sounds in their loaded order)
      defaultSoundOrder = sounds.map(\.fileName)
      UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
      Logger.audio.debug(
        "AudioManager: Initialized default sound order with \(self.defaultSoundOrder.count) sounds")
    }
  }

  private func loadBuiltInSounds() {
    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json") else {
      Logger.audio.debug("AudioManager: sounds.json file not found in Resources folder")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let soundsContainer = try decoder.decode(SoundsContainer.self, from: data)

      soundsData = soundsContainer.sounds.sorted(by: { $0.defaultOrder < $1.defaultOrder })

      let builtInSounds = soundsContainer.sounds
        .sorted(by: { $0.defaultOrder < $1.defaultOrder })
        .map { createSoundFromData($0) }

      // Add built-in sounds to the sounds array
      sounds.append(contentsOf: builtInSounds)

      // Migrate user preferences from old format (with extensions) to new format (without extensions)
      migrateUserPreferences(for: builtInSounds)

      Logger.audio.debug("AudioManager: Loaded \(builtInSounds.count) built-in sounds")
    } catch {
      Logger.audio.error("AudioManager: Failed to parse sounds.json: \(error, privacy: .public)")
      ErrorReporter.shared.report(error)
    }
  }

  private func createSoundFromData(_ soundData: SoundData) -> Sound {
    let supportedExtensions = ["m4a", "wav", "mp3", "aiff"]

    // Check if fileName already has an extension
    let hasExtension = supportedExtensions.contains { soundData.fileName.hasSuffix(".\($0)") }

    let (cleanedFileName, fileExtension) = extractFileNameAndExtension(
      soundData.fileName, hasExtension: hasExtension, supportedExtensions: supportedExtensions
    )

    // Check for cached playback profile
    let profileKey = "\(cleanedFileName).\(fileExtension)"
    let cachedProfile = PlaybackProfileStore.shared.profile(for: profileKey)

    // Use cached values if available and newer than JSON data
    let lufs = cachedProfile?.integratedLUFS ?? soundData.lufs
    let normalizationFactor =
      cachedProfile != nil
      ? pow(10, cachedProfile!.gainDB / 20) : soundData.normalizationFactor

    return Sound(
      title: soundData.title,
      systemIconName: soundData.systemIconName,
      fileName: cleanedFileName,
      fileExtension: fileExtension,
      defaultOrder: soundData.defaultOrder,
      lufs: lufs,
      normalizationFactor: normalizationFactor,
      truePeakdBTP: cachedProfile?.truePeakdBTP ?? soundData.truePeakdBTP,
      needsLimiter: cachedProfile?.needsLimiter ?? soundData.needsLimiter ?? false,
      isMusic: soundData.isMusic ?? false,
      duration: soundData.duration
    )
  }

  private func extractFileNameAndExtension(
    _ fileName: String, hasExtension: Bool, supportedExtensions: [String]
  ) -> (String, String) {
    if hasExtension {
      // Old format: fileName has extension, extract it
      let detectedExtension =
        supportedExtensions.first { fileName.hasSuffix(".\($0)") } ?? "mp3"
      let cleanedFileName = fileName.replacingOccurrences(
        of: ".\(detectedExtension)", with: ""
      )
      return (cleanedFileName, detectedExtension)
    } else {
      // New format: fileName has no extension, detect from bundle
      let fileExtension =
        supportedExtensions.first {
          Bundle.main.url(forResource: fileName, withExtension: $0) != nil
        } ?? "mp3"
      return (fileName, fileExtension)
    }
  }

  /// Load specific custom sounds by their IDs
  @MainActor
  func loadCustomSoundsByIds(_ ids: Set<UUID>) {
    Logger.audio.debug("AudioManager: Loading \(ids.count) specific custom sounds")

    // Get only the requested custom sounds from the database
    let allCustomSounds = CustomSoundManager.shared.getAllCustomSounds()
    let customSoundData = allCustomSounds.filter { ids.contains($0.id) }

    // Remove any existing custom sounds with these IDs to avoid duplicates.
    // Tear them down first (the same recipe as stopAndRemoveCustomSounds): a
    // removed-but-still-playing instance is no longer in `sounds`, so nothing
    // could ever stop it, and its player would stay retained in the engine.
    for sound in sounds
    where sound.isCustom && (sound.customSoundDataID.map { ids.contains($0) } ?? false) {
      sound.unload()
      sound.isSelected = false
    }
    sounds.removeAll { sound in
      guard sound.isCustom, let customId = sound.customSoundDataID else { return false }
      return ids.contains(customId)
    }

    // Create Sound objects for each custom sound
    let customSounds = customSoundData.enumerated().compactMap { index, data -> Sound? in
      createCustomSound(from: data, index: sounds.count + index)
    }

    // Add custom sounds to the array
    sounds.append(contentsOf: customSounds)
    Logger.audio.debug("AudioManager: Loaded \(customSounds.count) specific custom sounds")

    // Update default sound order if needed
    let newCustomFileNames = customSounds.map(\.fileName)
    var orderUpdated = false
    for fileName in newCustomFileNames where !defaultSoundOrder.contains(fileName) {
      defaultSoundOrder.append(fileName)
      orderUpdated = true
    }
    if orderUpdated {
      UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
    }

    // Re-setup observers for the new sounds
    refreshSoundDerivedState()
  }

  @MainActor
  func loadCustomSounds() {
    Logger.audio.debug("AudioManager: Loading custom sounds")

    // Deferred so the one-time duration backfill can't starve launch work.
    Task(priority: .background) {
      try? await Task.sleep(for: .seconds(5))
      await CustomSoundManager.shared.backfillDurations()
    }

    // Get all custom sounds from the database
    let customSoundData = CustomSoundManager.shared.getAllCustomSounds()

    // Stop and remove existing custom sounds, preserving their state
    let savedCustomSoundState = stopAndRemoveCustomSounds()

    // Create Sound objects for each custom sound
    let customSounds = customSoundData.enumerated().compactMap { index, data -> Sound? in
      createCustomSound(from: data, index: index)
    }

    // Add custom sounds to the array
    sounds.append(contentsOf: customSounds)

    // Restore the saved selection and volume state
    for sound in customSounds {
      if let savedState = savedCustomSoundState[sound.fileName] {
        sound.isSelected = savedState.isSelected
        sound.volume = savedState.volume
        Logger.audio.debug(
          "AudioManager: Restored state for '\(sound.fileName)' - selected: \(savedState.isSelected), volume: \(savedState.volume)"
        )
      }
    }

    Logger.audio.debug("AudioManager: Loaded \(customSounds.count) custom sounds")

    // Clean up orphaned custom sound UUIDs from defaultSoundOrder
    cleanupOrphanedSoundOrder()

    // Add new custom sounds to default sound order
    let newCustomFileNames = customSounds.map(\.fileName)
    var orderUpdated = false
    for fileName in newCustomFileNames where !defaultSoundOrder.contains(fileName) {
      defaultSoundOrder.append(fileName)
      orderUpdated = true
    }
    if orderUpdated {
      UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
      Logger.audio.debug("AudioManager: Updated default sound order with new custom sounds")
    }

    // Re-setup observers for the new sounds
    refreshSoundDerivedState()

    // Deferred so preset cleanup can't starve the preset-apply task.
    Task(priority: .background) { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      PresetManager.shared.cleanupDeletedCustomSounds()
    }
  }

  /// Rebuilds every loaded player when the session starts or ends (the mono
  /// fold and graph chain are decided at load time); position/resume
  /// semantics live in rebuildPlayerForSpatialChange.
  @MainActor
  func applySpatialAudioSetting() {
    for sound in sounds where sound.isLoaded {
      sound.rebuildPlayerForSpatialChange()
    }
  }

  private func stopAndRemoveCustomSounds() -> [String: (isSelected: Bool, volume: Float)] {
    let customSoundsToRemove = sounds.filter { $0.isCustom }
    var savedState: [String: (isSelected: Bool, volume: Float)] = [:]

    for sound in customSoundsToRemove {
      // Save the current state before removal so it can be restored onto the
      // new instance.
      savedState[sound.fileName] = (isSelected: sound.isSelected, volume: sound.volume)

      // Stop, detach from the engine, and deselect unconditionally. This
      // instance is leaving `sounds` but may still be retained (a grid tile,
      // or a pending auto-play closure from `Sound.isSelected.didSet`). If we
      // leave it selected, that closure can call `play()` on it after removal
      // — and since it is no longer in `sounds`, nothing (pauseAll / disable
      // loop / updatePlayingSounds) can ever stop it. Clearing `isSelected`
      // also makes those closures no-op; unloading frees its engine nodes.
      sound.unload()
      sound.isSelected = false
    }
    sounds.removeAll(where: { $0.isCustom })

    return savedState
  }

  private func createCustomSound(from data: CustomSoundData, index: Int) -> Sound? {
    guard let url = CustomSoundManager.shared.getURLForCustomSound(data) else {
      Logger.audio.error(
        "AudioManager: Could not get URL for custom sound \(data.fileName, privacy: .public)")
      return nil
    }

    // Ensure customization exists
    ensureCustomizationExists(for: data)

    // Get playback profile
    let profile = getPlaybackProfile(for: data)

    return Sound(
      title: data.title,
      systemIconName: data.systemIconName,
      fileName: data.fileName,
      fileExtension: data.fileExtension,
      defaultOrder: sounds.count + index,
      lufs: profile.lufs,
      normalizationFactor: profile.normalizationFactor,
      truePeakdBTP: profile.truePeakdBTP,
      needsLimiter: profile.needsLimiter,
      isCustom: true,
      fileURL: url,
      dateAdded: data.dateAdded,
      customSoundDataID: data.id,
      duration: data.duration
    )
  }

  private func ensureCustomizationExists(for data: CustomSoundData) {
    let existingCustomization = SoundCustomizationManager.shared.getCustomization(
      for: data.fileName)
    if existingCustomization == nil {
      // Create customization for the custom sound using individual setters
      let manager = SoundCustomizationManager.shared

      // Only set values that differ from defaults to avoid creating unnecessary customizations
      if data.title != data.fileName {
        manager.setCustomTitle(data.title, for: data.fileName)
      }
      if data.systemIconName != "waveform.circle" {
        manager.setCustomIcon(data.systemIconName, for: data.fileName)
      }
      if data.randomizeStartPosition != true {
        manager.setRandomizeStartPosition(data.randomizeStartPosition, for: data.fileName)
      }
      if data.normalizeAudio != true {
        manager.setNormalizeAudio(data.normalizeAudio, for: data.fileName)
      }
      if data.volumeAdjustment != 1.0 {
        manager.setVolumeAdjustment(data.volumeAdjustment, for: data.fileName)
      }
      if data.loopSound != true {
        manager.setLoopSound(data.loopSound, for: data.fileName)
      }
    }
  }

  private struct PlaybackProfileData {
    let lufs: Float
    let normalizationFactor: Float
    let truePeakdBTP: Float?
    let needsLimiter: Bool
  }

  private func getPlaybackProfile(for data: CustomSoundData) -> PlaybackProfileData {
    let profileKey = data.fileName
    let cachedProfile = PlaybackProfileStore.shared.profile(for: profileKey)

    let lufs = cachedProfile?.integratedLUFS ?? data.detectedLUFS ?? -23.0
    let normalizationFactor =
      cachedProfile != nil ? pow(10, cachedProfile!.gainDB / 20) : (data.normalizationFactor ?? 1.0)

    return PlaybackProfileData(
      lufs: lufs,
      normalizationFactor: normalizationFactor,
      truePeakdBTP: cachedProfile?.truePeakdBTP,
      needsLimiter: cachedProfile?.needsLimiter ?? false
    )
  }

  private struct SoundsContainer: Codable {
    let sounds: [SoundData]
  }

  /// Migrates user preferences from old format (with file extensions) to new format (without extensions)
  private func migrateUserPreferences(for sounds: [Sound]) {
    let userDefaults = UserDefaults.shared
    let legacyExtensions = ["mp3", "m4a", "wav", "aiff"]

    for sound in sounds {
      let newFileName = sound.fileName

      // Try to find preferences with legacy extensions
      for ext in legacyExtensions {
        let legacyFileName = "\(newFileName).\(ext)"

        // Migrate isSelected
        if let legacyIsSelected = userDefaults.object(forKey: "\(legacyFileName)_isSelected")
          as? Bool
        {
          userDefaults.set(legacyIsSelected, forKey: "\(newFileName)_isSelected")
          userDefaults.removeObject(forKey: "\(legacyFileName)_isSelected")
          Logger.audio.debug(
            "AudioManager: Migrated isSelected for '\(legacyFileName)' -> '\(newFileName)'")
        }

        // Migrate volume
        if let legacyVolume = userDefaults.object(forKey: "\(legacyFileName)_volume") as? Float {
          userDefaults.set(legacyVolume, forKey: "\(newFileName)_volume")
          userDefaults.removeObject(forKey: "\(legacyFileName)_volume")
          Logger.audio.debug(
            "AudioManager: Migrated volume for '\(legacyFileName)' -> '\(newFileName)'")
        }

        // customOrder is no longer used - managed by individual presets
        userDefaults.removeObject(forKey: "\(legacyFileName)_customOrder")

        // Migrate isHidden
        if let legacyHidden = userDefaults.object(forKey: "\(legacyFileName)_isHidden") as? Bool {
          userDefaults.set(legacyHidden, forKey: "\(newFileName)_isHidden")
          userDefaults.removeObject(forKey: "\(legacyFileName)_isHidden")
          Logger.audio.debug(
            "AudioManager: Migrated isHidden for '\(legacyFileName)' -> '\(newFileName)'")
        }
      }
    }
  }

  /// Removes orphaned UUID entries from defaultSoundOrder that no longer have corresponding sounds
  private func cleanupOrphanedSoundOrder() {
    let validSoundFileNames = Set(sounds.map(\.fileName))
    let originalCount = defaultSoundOrder.count

    // Filter out any entries that look like UUIDs and don't have corresponding sounds
    defaultSoundOrder = defaultSoundOrder.filter { fileName in
      // Check if this is a valid sound fileName
      if validSoundFileNames.contains(fileName) {
        return true
      }

      // Check if it looks like a UUID (8-4-4-4-12 format)
      let uuidPattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
      if fileName.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil {
        Logger.audio.debug(
          "AudioManager: Removing orphaned UUID from defaultSoundOrder: \(fileName)")
        return false
      }

      // Keep non-UUID entries that might be valid sound names
      return true
    }

    if defaultSoundOrder.count != originalCount {
      UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
      Logger.audio.debug(
        "AudioManager: Cleaned up \(originalCount - self.defaultSoundOrder.count) orphaned entries from defaultSoundOrder"
      )
    }
  }
}
