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
        // Persist the import sheet's non-default toggles (the import call
        // itself only carries randomization).
        let manager = SoundCustomizationManager.shared
        if loopSound != true {
          manager.setLoopSound(loopSound, for: customSound.fileName)
        }
        if fadeSound != true {
          manager.setFadeSound(fadeSound, for: customSound.fileName)
        }
        if isPresetUseOnly != false {
          manager.setPresetUseOnly(isPresetUseOnly, for: customSound.fileName)
        }
        if isMusic != false {
          manager.setMusic(isMusic, for: customSound.fileName)
        }

        // Add the new sound to the chosen presets (and/or a fresh
        // "<Name> Mix") after AudioManager loads it.
        let presetIDs = addToPresetIDs
        let makeMix = createMixPreset
        Task { @MainActor in
          await Task.yield()  // Allow AudioManager to process the new sound
          addImportedSound(
            fileName: customSound.fileName, title: title,
            toPresets: presetIDs, creatingMix: makeMix)
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
    let hasCustomFade = fadeSound != true  // Default is true
    let hasCustomPresetOnly = isPresetUseOnly != false  // Default is false
    let hasCustomMusic = isMusic != sound.isMusicDefault  // Default varies per sound

    return hasCustomName || hasCustomIcon || hasCustomRandomization
      || hasCustomNormalization || hasCustomVolume || hasCustomLoop || hasCustomFade
      || hasCustomPresetOnly || hasCustomMusic
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

    // Fade customization
    manager.setFadeSound(
      fadeSound != true ? fadeSound : nil,
      for: sound.fileName
    )

    // Preset-use-only customization
    manager.setPresetUseOnly(
      isPresetUseOnly != false ? isPresetUseOnly : nil,
      for: sound.fileName
    )

    // Music tag is user-editable only for custom sounds; built-ins keep their
    // sounds.json default, so never write an override for them. (The default
    // varies per sound, so diff against the sound's own default.)
    if sound.isCustom {
      manager.setMusic(
        isMusic != sound.isMusicDefault ? isMusic : nil,
        for: sound.fileName
      )
    }

    // Going preset-only (directly or via loop-off) hides the tile from the
    // default grid; if the sound is selected there it would keep playing with
    // no control to stop it. Deselect (fades out) — unless a custom preset is
    // showing it, or it's the active solo sound.
    if sound.isPresetUseOnly, sound.isSelected,
      PresetManager.shared.currentPreset?.isDefault ?? true,
      AudioManager.shared.soloModeSound?.id != sound.id
    {
      sound.isSelected = false
    }

    // Force save all customizations
    manager.saveCustomizations()
  }

  // MARK: - Preset Integration

  /// Adds the imported sound to every preset checked in Add to Presets, and
  /// optionally creates a fresh "<Name> Mix" preset containing just it.
  private func addImportedSound(
    fileName: String, title: String, toPresets presetIDs: Set<UUID>, creatingMix: Bool
  ) {
    let presetManager = PresetManager.shared
    let audioManager = AudioManager.shared

    guard !presetIDs.isEmpty || creatingMix else { return }

    // Find the newly imported sound
    guard let newSound = audioManager.sounds.first(where: { $0.fileName == fileName }) else {
      Logger.ui.error(
        "SoundSheet: Could not find imported sound with fileName: \(fileName, privacy: .public)")
      return
    }

    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    var presets = presetManager.presets
    var changed = false

    for index in presets.indices where presetIDs.contains(presets[index].id) {
      guard !presets[index].isDefault,
        !presets[index].soundStates.contains(where: { $0.fileName == fileName })
      else { continue }

      presets[index].soundStates.append(
        PresetState(
          fileName: fileName,
          isSelected: false,  // Start unselected so it doesn't interrupt current mix
          volume: newSound.volume
        ))
      presets[index].lastModifiedVersion = currentVersion
      changed = true

      // Keep the active preset's working copy in sync.
      if presetManager.currentPreset?.id == presets[index].id {
        presetManager.setCurrentPreset(presets[index])
      }
    }

    if creatingMix {
      presets.append(
        Preset(
          id: UUID(),
          // Format string so locales control the word order.
          name: String(localized: "\(title) Mix"),
          soundStates: [
            PresetState(fileName: fileName, isSelected: true, volume: newSound.volume)
          ],
          isDefault: false,
          createdVersion: currentVersion,
          lastModifiedVersion: currentVersion,
          soundOrder: nil,
          creatorName: nil,
          artworkId: nil,
          animatedArtwork: nil,
          staticArtworkPath: nil,
          order: presets.filter { !$0.isDefault }.count
        ))
      changed = true
    }

    guard changed else { return }
    presetManager.setPresets(presets)
    presetManager.updateCustomPresetStatus()

    // Save directly to avoid state override
    savePresetsDirectly()

    Logger.ui.debug(
      "SoundSheet: Added '\(title)' to \(presetIDs.count) preset(s); new Mix preset: \(creatingMix)"
    )
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
