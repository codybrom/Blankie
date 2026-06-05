//
//  SoundSheet+Actions.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import SwiftData
import SwiftUI
import os

extension SoundSheet {
  // MARK: - Actions

  func performAction() {
    // Stop preview before performing action
    if isPreviewing {
      stopPreview()
    }

    switch mode {
    case .add:
      importSound()
    case .edit:
      // For edit mode, just dismiss - changes are already applied
      dismiss()
    }
  }

  func importSound() {
    guard let selectedFile = selectedFile,
      !soundName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    else {
      return
    }

    isProcessing = true

    // Capture values before Task to avoid sendability issues
    let file = selectedFile
    let title = soundName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let icon = selectedIcon
    let randomize = randomizeStartPosition

    Task {
      let result = await CustomSoundManager.shared.importSound(
        from: file,
        title: title,
        iconName: icon,
        randomizeStartPosition: randomize
      )

      isProcessing = false

      switch result {
      case .success(let customSound):
        // Add the new sound to current preset after AudioManager loads it
        Task { @MainActor in
          await Task.yield()  // Allow AudioManager to process the new sound
          addNewSoundToCurrentPreset(fileName: customSound.fileName)
        }
        dismiss()
      case .failure(let error):
        importError = NSError(
          domain: "SoundImport",
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
        showingError = true
      }
    }
  }

  func applyCustomizationInstantly(_ sound: Sound) {
    applyCustomizations(sound)

    // Force an immediate volume update for the sound
    if sound.isLoaded {
      sound.updateVolume()
    }
  }

  private func checkForCustomizations(_ sound: Sound) -> Bool {
    let hasCustomName = soundName != sound.originalTitle
    let hasCustomIcon = selectedIcon != sound.originalSystemIconName
    let hasCustomRandomization = randomizeStartPosition != true  // Default is true
    let hasCustomNormalization = normalizeAudio != true  // Default is true
    let hasCustomVolume = volumeAdjustment != 1.0  // Default is 1.0
    let hasCustomLoop = loopSound != true  // Default is true

    return hasCustomName || hasCustomIcon || hasCustomRandomization
      || hasCustomNormalization || hasCustomVolume || hasCustomLoop
  }

  private func applyCustomizations(_ sound: Sound) {
    let manager = SoundCustomizationManager.shared

    // Name customization
    manager.setCustomTitle(
      soundName != sound.originalTitle ? soundName : nil,
      for: sound.fileName
    )

    // Icon customization
    manager.setCustomIcon(
      selectedIcon != sound.originalSystemIconName ? selectedIcon : nil,
      for: sound.fileName
    )

    // Randomization customization
    manager.setRandomizeStartPosition(
      randomizeStartPosition != true ? randomizeStartPosition : nil,
      for: sound.fileName
    )

    // Normalization customization
    manager.setNormalizeAudio(
      normalizeAudio != true ? normalizeAudio : nil,
      for: sound.fileName
    )

    // Volume customization
    manager.setVolumeAdjustment(
      volumeAdjustment != 1.0 ? volumeAdjustment : nil,
      for: sound.fileName
    )

    // Loop customization
    manager.setLoopSound(
      loopSound != true ? loopSound : nil,
      for: sound.fileName
    )

    // Force save all customizations
    manager.saveCustomizations()
  }

  // MARK: - Preset Integration

  private func addNewSoundToCurrentPreset(fileName: String) {
    let presetManager = PresetManager.shared
    let audioManager = AudioManager.shared

    // Only add to preset if:
    // 1. There's a current preset
    // 2. It's not the default preset (All Sounds)
    // 3. We're not in solo mode
    // 4. We're not in Quick Mix mode
    guard let currentPreset = presetManager.currentPreset,
      !currentPreset.isDefault,
      audioManager.soloModeSound == nil,
      !audioManager.isQuickMix
    else {
      Logger.ui.debug("SoundSheet: Not adding to preset - conditions not met")
      return
    }

    // Check if the sound is already in the preset
    let existingSoundFileNames = Set(currentPreset.soundStates.map(\.fileName))
    guard !existingSoundFileNames.contains(fileName) else {
      Logger.ui.debug("SoundSheet: Sound already exists in preset")
      return
    }

    // Find the newly imported sound
    guard let newSound = audioManager.sounds.first(where: { $0.fileName == fileName }) else {
      Logger.ui.error(
        "SoundSheet: Could not find imported sound with fileName: \(fileName, privacy: .public)")
      return
    }

    Logger.ui.debug("SoundSheet: Adding '\(newSound.title)' to preset '\(currentPreset.name)'")

    // Create a new preset state for the imported sound
    let newSoundState = PresetState(
      fileName: fileName,
      isSelected: false,  // Start unselected so it doesn't interrupt current mix
      volume: newSound.volume
    )

    // Update the preset with the new sound
    var updatedPreset = currentPreset
    updatedPreset.soundStates.append(newSoundState)
    updatedPreset.lastModifiedVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // Update the preset in the manager
    var currentPresets = presetManager.presets
    if let index = currentPresets.firstIndex(where: { $0.id == currentPreset.id }) {
      currentPresets[index] = updatedPreset
      presetManager.setPresets(currentPresets)
      presetManager.setCurrentPreset(updatedPreset)

      // Save directly to avoid state override
      savePresetsDirectly()

      Logger.ui.debug(
        "SoundSheet: Successfully added sound to preset (now has \(updatedPreset.soundStates.count) sounds)"
      )
    }
  }

  // MARK: - Delete Action

  func deleteSound() {
    guard case .edit(let sound) = mode,
      sound.isCustom,
      let customSoundDataID = sound.customSoundDataID,
      let customSound = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
    else {
      return
    }

    // Stop preview before deleting
    if isPreviewing {
      stopPreview()
    }

    let result = CustomSoundManager.shared.deleteCustomSound(customSound)

    switch result {
    case .success:
      // Remove any customizations for this sound
      SoundCustomizationManager.shared.removeCustomization(for: customSound.fileName)

      // Reload custom sounds in AudioManager
      AudioManager.shared.loadCustomSounds()

      dismiss()
    case .failure(let error):
      importError = error
      showingError = true
    }
  }

  // MARK: - Direct Preset Saving

  private func savePresetsDirectly() {
    let presetManager = PresetManager.shared
    let defaultPreset = presetManager.presets.first { $0.isDefault }
    let customPresets = presetManager.presets.filter { !$0.isDefault }

    if let defaultPreset = defaultPreset {
      PresetStorage.saveDefaultPreset(defaultPreset)
    }
    PresetStorage.saveCustomPresets(customPresets)
    Logger.ui.debug("SoundSheet: Presets saved directly without state override")
  }

  // MARK: - Dismiss Action

  func handleDismiss() {
    // Stop preview before dismissing
    if isPreviewing {
      stopPreview()
    }
    dismiss()
  }
}
