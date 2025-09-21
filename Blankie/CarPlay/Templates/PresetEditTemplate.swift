//
//  PresetEditTemplate.swift
//  Blankie
//
//  Created by Assistant on 12/21/24.
//

#if CARPLAY_ENABLED

  import CarPlay
  import SwiftUI

  enum PresetEditTemplate {
    // MARK: - Main Edit Template

    static func createTemplate() -> CPListTemplate {
      // Get current preset name for the title
      let currentPreset = PresetManager.shared.currentPreset
      let presetName = currentPreset?.name ?? "Current Mix"

      let template = CPListTemplate(
        title: presetName,
        sections: []
      )

      updateTemplate(template)
      return template
    }

    static func updateTemplate(_ template: CPListTemplate) {
      // Get the current preset to determine which sounds to show
      guard let currentPreset = PresetManager.shared.currentPreset else {
        let noPresetItem = CPListItem(text: "No preset selected", detailText: nil)
        let section = CPListSection(items: [noPresetItem])
        template.updateSections([section])
        return
      }

      // Get only sounds that are part of the current preset
      let presetSounds = AudioManager.shared.sounds.filter { sound in
        // Check if this sound is in the current preset by checking the sound order
        currentPreset.soundOrder?.contains(sound.fileName) ?? false
      }

      guard !presetSounds.isEmpty else {
        let emptySoundsItem = CPListItem(text: "No sounds in this preset", detailText: nil)
        let section = CPListSection(items: [emptySoundsItem])
        template.updateSections([section])
        return
      }

      // Sort sounds alphabetically
      let sortedSounds = presetSounds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

      let items = sortedSounds.map { sound in
        createSoundEditItem(sound)
      }

      let section = CPListSection(
        items: items,
        header: nil,
        sectionIndexTitle: nil
      )

      template.updateSections([section])
    }

    private static func createSoundEditItem(_ sound: Sound) -> CPListItem {
      let isSelected = sound.isSelected
      let volumeText = "\(Int(sound.volume * 100))%"

      let item = CPListItem(
        text: sound.title,
        detailText: isSelected ? "ON • \(volumeText)" : "OFF"
      )

      // Always show disclosure indicator since we can adjust volume or turn on/off
      item.accessoryType = .disclosureIndicator

      item.handler = { _, completion in
        Task { @MainActor in
          if sound.isSelected {
            // Sound is currently ON - show volume adjustment options
            CarPlayInterfaceController.shared.showVolumeAdjustment(for: sound)
          } else {
            // Sound is currently OFF - show options to turn ON with volume selection
            CarPlayInterfaceController.shared.showTurnOnOptions(for: sound)
          }

          completion()
        }
      }

      return item
    }

    // MARK: - Volume Adjustment Template

    static func createVolumeAdjustmentTemplate(for sound: Sound) -> CPListTemplate {
      let template = CPListTemplate(
        title: "\(sound.title) Volume",
        sections: []
      )

      var items: [CPListItem] = []

      // Current volume display
      items.append(createCurrentVolumeItem(for: sound))

      // Option to turn OFF the sound
      items.append(createTurnOffItem(for: sound))

      // Volume options (10% increments)
      items.append(contentsOf: createVolumeItems(for: sound))

      let section = CPListSection(items: items)
      template.updateSections([section])

      return template
    }

    private static func createCurrentVolumeItem(for sound: Sound) -> CPListItem {
      let currentVolumeText = "\(Int(sound.volume * 100))%"
      let item = CPListItem(
        text: "\(currentVolumeText) Volume",
        detailText: nil
      )
      item.isEnabled = false
      return item
    }

    private static func createTurnOffItem(for sound: Sound) -> CPListItem {
      let item = CPListItem(
        text: "Stop",
        detailText: "Turn off this sound"
      )
      item.handler = { _, completion in
        Task { @MainActor in
          sound.isSelected = false
          sound.pause()
          AudioManager.shared.updateHasSelectedSounds()
          PresetManager.shared.savePresets()
          CarPlayInterfaceController.shared.popAndRefreshEditTemplate()
          completion()
        }
      }
      return item
    }

    private static func createVolumeItems(for sound: Sound) -> [CPListItem] {
      return stride(from: 100, through: 10, by: -10).map { percentage in
        let volume = Float(percentage) / 100.0
        let isCurrentVolume = abs(sound.volume - volume) < 0.01

        let item = CPListItem(
          text: "\(percentage)%",
          detailText: isCurrentVolume ? "Current" : nil
        )

        if isCurrentVolume {
          item.accessoryType = .disclosureIndicator
        }

        item.handler = { _, completion in
          Task { @MainActor in
            sound.volume = volume
            AudioManager.shared.updateHasSelectedSounds()
            PresetManager.shared.savePresets()
            CarPlayInterfaceController.shared.popAndRefreshEditTemplate()
            completion()
          }
        }

        return item
      }
    }

    // MARK: - Turn On Template

    static func createTurnOnTemplate(for sound: Sound) -> CPListTemplate {
      let template = CPListTemplate(
        title: nil,
        sections: []
      )

      var items: [CPListItem] = []

      // Header text
      let headerItem = CPListItem(
        text: "Choose a volume to start \(sound.title)",
        detailText: nil
      )
      headerItem.isEnabled = false
      items.append(headerItem)

      // Volume options (10% increments, highest first)
      for percentage in stride(from: 100, through: 10, by: -10) {
        let volume = Float(percentage) / 100.0

        let item = CPListItem(
          text: "\(percentage)%",
          detailText: nil
        )

        item.handler = { _, completion in
          Task { @MainActor in
            // Turn on the sound with selected volume
            sound.isSelected = true
            sound.volume = volume

            // If global playback is active, start playing this sound
            if AudioManager.shared.isGloballyPlaying {
              sound.play()
            }

            // Update AudioManager state
            AudioManager.shared.updateHasSelectedSounds()

            // Save the change
            PresetManager.shared.savePresets()

            // Pop back and refresh
            CarPlayInterfaceController.shared.popAndRefreshEditTemplate()

            completion()
          }
        }

        items.append(item)
      }

      let section = CPListSection(items: items)
      template.updateSections([section])

      return template
    }
  }

#endif
