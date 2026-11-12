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
    if isPreviewing {
      stopPreview()
    }

    switch mode {
    case .add:
      importSound()
    case .edit:
      // Edits apply live, so edit mode only dismisses.
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
    importProgress = nil
    let attempt = UUID()
    importAttempt = attempt

    // Capture values before Task to avoid sendability issues
    let file = selectedFile
    let title = soundName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let icon = selectedIcon
    let randomize = randomizeStartPosition
    let convert = convertToAACOnImport

    importTask = Task {
      #if os(iOS) || os(visionOS)
        let backgroundTime = ImportBackgroundTime()
        defer { backgroundTime.end() }
      #endif

      let result = await CustomSoundManager.shared.importSound(
        from: file,
        title: title,
        iconName: icon,
        randomizeStartPosition: randomize,
        convertToAAC: convert
      ) { progress in
        Task { @MainActor in
          // Updates hop to the main actor separately, so drop any that arrive late or
          // come from an import that was cancelled.
          if importAttempt == attempt, progress.fraction >= importProgress?.fraction ?? 0 {
            importProgress = progress
          }
        }
      }

      // Cancel already reset the sheet and the import removed its files.
      guard !Task.isCancelled else { return }
      isProcessing = false
      importTask = nil

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

  /// Stops a running import and returns to the form with everything still filled in.
  func cancelImport() {
    importTask?.cancel()
    importTask = nil
    importAttempt = nil
    importProgress = nil
    isProcessing = false
  }

  func applyCustomizationInstantly(_ sound: Sound) {
    applyCustomizations(sound)

    if sound.isLoaded {
      sound.updateVolume()
    }
  }

  private func checkForCustomizations(_ sound: Sound) -> Bool {
    let hasCustomName = soundName != sound.originalTitle
    let hasCustomIcon = selectedIcon != sound.originalSystemIconName
    let hasCustomRandomization = randomizeStartPosition != true
    let hasCustomNormalization = normalizeAudio != true
    let hasCustomVolume = volumeAdjustment != 1.0
    let hasCustomLoop = loopSound != true
    let hasCustomFade = fadeSound != true
    let hasCustomPresetOnly = isPresetUseOnly != false
    let hasCustomMusic = isMusic != sound.isMusicDefault

    return hasCustomName || hasCustomIcon || hasCustomRandomization
      || hasCustomNormalization || hasCustomVolume || hasCustomLoop || hasCustomFade
      || hasCustomPresetOnly || hasCustomMusic
  }

  private func applyCustomizations(_ sound: Sound) {
    let manager = SoundCustomizationManager.shared

    manager.setCustomTitle(
      soundName != sound.originalTitle ? soundName : nil,
      for: sound.fileName
    )

    manager.setCustomIcon(
      selectedIcon != sound.originalSystemIconName ? selectedIcon : nil,
      for: sound.fileName
    )

    manager.setRandomizeStartPosition(
      randomizeStartPosition != true ? randomizeStartPosition : nil,
      for: sound.fileName
    )

    manager.setNormalizeAudio(
      normalizeAudio != true ? normalizeAudio : nil,
      for: sound.fileName
    )

    manager.setVolumeAdjustment(
      volumeAdjustment != 1.0 ? volumeAdjustment : nil,
      for: sound.fileName
    )

    manager.setLoopSound(
      loopSound != true ? loopSound : nil,
      for: sound.fileName
    )

    manager.setFadeSound(
      fadeSound != true ? fadeSound : nil,
      for: sound.fileName
    )

    manager.setPresetUseOnly(
      isPresetUseOnly != false ? isPresetUseOnly : nil,
      for: sound.fileName
    )

    // Only custom sounds take a music override. Built-ins keep their sounds.json
    // default. The default varies per sound, so diff against the sound's own.
    if sound.isCustom {
      manager.setMusic(
        isMusic != sound.isMusicDefault ? isMusic : nil,
        for: sound.fileName
      )
    }

    // A preset-only sound (set directly or via loop-off) has no tile in the
    // default preset, so deselect it unless a custom preset or single sound shows it.
    if sound.isPresetUseOnly, sound.isSelected,
      PresetManager.shared.currentPreset?.isDefault ?? true,
      AudioManager.shared.singleSound?.id != sound.id
    {
      sound.isSelected = false
    }

    manager.saveCustomizations()

    // The player bakes in the loop flag at load, so a loop edit rebuilds it.
    // Runs after the deselect above so a sound loop-off just removed stays off.
    sound.reloadForLoopChange()
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

    if isPreviewing {
      stopPreview()
    }

    let result = CustomSoundManager.shared.deleteCustomSound(customSound)

    switch result {
    case .success:
      // Drop only the deleted sound, so single sound, preview and Quick Mix keep the
      // Sound instances they hold.
      AudioManager.shared.syncCustomSounds()

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
    // This bypasses savePresets, so refresh the Siri/Spotlight names and widgets it would.
    presetManager.refreshDiscoverableEntitiesIfNeeded()
    AudioManager.shared.republishWidgetCatalog()
  }

  // MARK: - Dismiss Action

  func handleDismiss() {
    if isPreviewing {
      stopPreview()
    }
    dismiss()
  }
}

#if os(iOS) || os(visionOS)
  /// Asks iOS for extra time so an import keeps running for a while after Blankie
  /// leaves the foreground. Ends itself if that time runs out.
  @MainActor private final class ImportBackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init() {
      identifier = UIApplication.shared.beginBackgroundTask(withName: "Import Sound") {
        [weak self] in self?.end()
      }
    }

    func end() {
      guard identifier != .invalid else { return }
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
    }
  }
#endif
