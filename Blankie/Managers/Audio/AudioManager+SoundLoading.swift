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

    sounds = []
    loadBuiltInSounds()

    // Custom sounds add themselves to the order when they load.
    if let savedOrder = UserDefaults.shared.stringArray(forKey: "defaultSoundOrder") {
      defaultSoundOrder = savedOrder
      Logger.audio.debug("AudioManager: Loaded default sound order with \(savedOrder.count) sounds")

      // Append built-in sounds added since the order was saved.
      let currentSoundFileNames = Set(sounds.map(\.fileName))
      let savedOrderSet = Set(savedOrder)
      let newSounds = currentSoundFileNames.subtracting(savedOrderSet)

      if !newSounds.isEmpty {
        defaultSoundOrder.append(contentsOf: newSounds)
        UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
        Logger.audio.debug("AudioManager: Added \(newSounds.count) new sounds to default order")
      }
    } else {
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

      sounds.append(contentsOf: builtInSounds)

      migrateUserPreferences(for: builtInSounds)

      Logger.audio.debug("AudioManager: Loaded \(builtInSounds.count) built-in sounds")
    } catch {
      Logger.audio.error("AudioManager: Failed to parse sounds.json: \(error, privacy: .public)")
      ErrorReporter.shared.report(error)
    }
  }

  private func createSoundFromData(_ soundData: SoundData) -> Sound {
    let supportedExtensions = ["m4a", "wav", "mp3", "aiff"]

    let hasExtension = supportedExtensions.contains { soundData.fileName.hasSuffix(".\($0)") }

    let (cleanedFileName, fileExtension) = extractFileNameAndExtension(
      soundData.fileName, hasExtension: hasExtension, supportedExtensions: supportedExtensions
    )

    let profileKey = "\(cleanedFileName).\(fileExtension)"
    let cachedProfile = PlaybackProfileStore.shared.profile(for: profileKey)

    // A cached playback profile overrides the values in sounds.json.
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
      // Legacy sounds.json entries include the extension.
      let detectedExtension =
        supportedExtensions.first { fileName.hasSuffix(".\($0)") } ?? "mp3"
      let cleanedFileName = fileName.replacingOccurrences(
        of: ".\(detectedExtension)", with: ""
      )
      return (cleanedFileName, detectedExtension)
    } else {
      // Otherwise find the extension in the bundle.
      let fileExtension =
        supportedExtensions.first {
          Bundle.main.url(forResource: fileName, withExtension: $0) != nil
        } ?? "mp3"
      return (fileName, fileExtension)
    }
  }

  @MainActor
  func loadCustomSoundsByIds(_ ids: Set<UUID>) {
    Logger.audio.debug("AudioManager: Loading \(ids.count) specific custom sounds")

    let allCustomSounds = CustomSoundManager.shared.getAllCustomSounds()
    let customSoundData = allCustomSounds.filter { ids.contains($0.id) }

    // Replace existing instances with these IDs, torn down as in
    // stopAndRemoveCustomSounds.
    for sound in sounds
    where sound.isCustom && (sound.customSoundDataID.map { ids.contains($0) } ?? false) {
      sound.unload()
      sound.isSelected = false
    }
    sounds.removeAll { sound in
      guard sound.isCustom, let customId = sound.customSoundDataID else { return false }
      return ids.contains(customId)
    }

    let customSounds = customSoundData.enumerated().compactMap { index, data -> Sound? in
      createCustomSound(from: data, index: sounds.count + index)
    }

    sounds.append(contentsOf: customSounds)
    Logger.audio.debug("AudioManager: Loaded \(customSounds.count) specific custom sounds")

    let newCustomFileNames = customSounds.map(\.fileName)
    var orderUpdated = false
    for fileName in newCustomFileNames where !defaultSoundOrder.contains(fileName) {
      defaultSoundOrder.append(fileName)
      orderUpdated = true
    }
    if orderUpdated {
      UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
    }

    refreshSoundDerivedState()
  }

  /// Applies a custom-sound add or delete without rebuilding unchanged sounds,
  /// since solo, preview and Quick Mix hold `Sound` instances.
  @MainActor
  func syncCustomSounds() {
    let rowIDs = Set(CustomSoundManager.shared.getAllCustomSounds().map(\.id))
    let loadedIDs = Set(sounds.compactMap { $0.isCustom ? $0.customSoundDataID : nil })

    let removedIDs = loadedIDs.subtracting(rowIDs)
    if !removedIDs.isEmpty {
      // Same teardown as stopAndRemoveCustomSounds.
      for sound in sounds
      where sound.isCustom && (sound.customSoundDataID.map { removedIDs.contains($0) } ?? false) {
        sound.unload()
        sound.isSelected = false
      }
      sounds.removeAll { sound in
        guard sound.isCustom, let customId = sound.customSoundDataID else { return false }
        return removedIDs.contains(customId)
      }
      cleanupOrphanedSoundOrder()
    }

    let addedIDs = rowIDs.subtracting(loadedIDs)
    if !addedIDs.isEmpty {
      loadCustomSoundsByIds(addedIDs)
    } else if !removedIDs.isEmpty {
      refreshSoundDerivedState()
    }
  }

  @MainActor
  func loadCustomSounds() {
    Logger.audio.debug("AudioManager: Loading custom sounds")

    // Deferred so the one-time duration backfill doesn't compete with launch work.
    Task(priority: .background) {
      try? await Task.sleep(for: .seconds(5))
      await CustomSoundManager.shared.backfillDurations()
    }

    let customSoundData = CustomSoundManager.shared.getAllCustomSounds()
    let savedCustomSoundState = stopAndRemoveCustomSounds()

    let customSounds = customSoundData.enumerated().compactMap { index, data -> Sound? in
      createCustomSound(from: data, index: index)
    }

    sounds.append(contentsOf: customSounds)

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

    cleanupOrphanedSoundOrder()

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

    refreshSoundDerivedState()

    // Deferred so preset cleanup doesn't delay the preset-apply task.
    Task(priority: .background) { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      PresetManager.shared.cleanupDeletedCustomSounds()
    }
  }

  /// Rebuilds every loaded player when a spatial session starts or ends, since the
  /// mono fold and graph chain are fixed at load time.
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
      savedState[sound.fileName] = (isSelected: sound.isSelected, volume: sound.volume)

      // A removed instance can still be retained (a tile, a pending auto-play
      // closure), and nothing outside `sounds` can stop it. Deselecting makes those
      // closures no-op; unloading frees its engine nodes.
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

    ensureCustomizationExists(for: data)
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
      let manager = SoundCustomizationManager.shared

      // Only non-default values. Title is skipped: Sound.title already falls back to
      // data.title, and a customTitle here could mask a real rename.
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

  /// Moves per-sound UserDefaults keys from legacy names with file extensions to bare names.
  private func migrateUserPreferences(for sounds: [Sound]) {
    let userDefaults = UserDefaults.shared
    let legacyExtensions = ["mp3", "m4a", "wav", "aiff"]

    for sound in sounds {
      let newFileName = sound.fileName

      for ext in legacyExtensions {
        let legacyFileName = "\(newFileName).\(ext)"

        if let legacyIsSelected = userDefaults.object(forKey: "\(legacyFileName)_isSelected")
          as? Bool
        {
          userDefaults.set(legacyIsSelected, forKey: "\(newFileName)_isSelected")
          userDefaults.removeObject(forKey: "\(legacyFileName)_isSelected")
          Logger.audio.debug(
            "AudioManager: Migrated isSelected for '\(legacyFileName)' -> '\(newFileName)'")
        }

        if let legacyVolume = userDefaults.object(forKey: "\(legacyFileName)_volume") as? Float {
          userDefaults.set(legacyVolume, forKey: "\(newFileName)_volume")
          userDefaults.removeObject(forKey: "\(legacyFileName)_volume")
          Logger.audio.debug(
            "AudioManager: Migrated volume for '\(legacyFileName)' -> '\(newFileName)'")
        }

        // Presets own sound order now.
        userDefaults.removeObject(forKey: "\(legacyFileName)_customOrder")

        if let legacyHidden = userDefaults.object(forKey: "\(legacyFileName)_isHidden") as? Bool {
          userDefaults.set(legacyHidden, forKey: "\(newFileName)_isHidden")
          userDefaults.removeObject(forKey: "\(legacyFileName)_isHidden")
          Logger.audio.debug(
            "AudioManager: Migrated isHidden for '\(legacyFileName)' -> '\(newFileName)'")
        }
      }
    }
  }

  /// Drops UUID-named (custom sound) entries from defaultSoundOrder that no longer
  /// match a loaded sound.
  private func cleanupOrphanedSoundOrder() {
    let validSoundFileNames = Set(sounds.map(\.fileName))
    let originalCount = defaultSoundOrder.count

    defaultSoundOrder = defaultSoundOrder.filter { fileName in
      if validSoundFileNames.contains(fileName) {
        return true
      }

      let uuidPattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
      if fileName.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil {
        Logger.audio.debug(
          "AudioManager: Removing orphaned UUID from defaultSoundOrder: \(fileName)")
        return false
      }

      // Non-UUID names might still be valid sounds.
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
