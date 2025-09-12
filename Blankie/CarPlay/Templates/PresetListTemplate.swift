//
// PresetListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

#if CARPLAY_ENABLED

  import CarPlay
  import SwiftUI

  enum PresetListTemplate {

    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(
        title: "Presets",
        sections: []
      )

      // Set tab image
      template.tabImage = UIImage(systemName: "list.bullet")

      updateTemplate(template)
      return template
    }

    static func updateTemplate(_ template: CPListTemplate) {
      let customPresets = PresetManager.shared.presets.filter { !$0.isDefault }
      let defaultPreset = PresetManager.shared.presets.first { $0.isDefault }

      var sections: [CPListSection] = []

      addRecentSection(to: &sections)

      if !customPresets.isEmpty {
        addCustomPresetsSection(to: &sections, customPresets: customPresets)
        addAllSoundsSection(to: &sections, defaultPreset: defaultPreset)
      } else {
        addEmptyStateSection(to: &sections, defaultPreset: defaultPreset)
      }

      template.updateSections(sections)
    }

    private static func createPresetListItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: preset.name,
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      // Add checkmark accessory if active
      if isActive {
        item.accessoryType = .disclosureIndicator
        // Update text to show active state
        item.setText("\(preset.name) ✓")
      }

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Exit solo mode without resuming previous sounds if active
              // This prevents the previous preset from briefly playing
              if AudioManager.shared.soloModeSound != nil {
                AudioManager.shared.exitSoloModeWithoutResuming()
              }

              // Exit Quick Mix mode if active
              if AudioManager.shared.isQuickMix {
                AudioManager.shared.exitQuickMix()
              }
            }

            try await PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Ensure playback starts
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            print("🚗 CarPlay: Error applying preset: \(error)")
          }
          completion()
        }
      }

      return item
    }

    private static func createCurrentSoundscapeItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: "Current Soundscape",
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      if isActive {
        item.accessoryType = .disclosureIndicator
        item.setText("Current Soundscape ✓")
      }

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Exit solo mode without resuming previous sounds if active
              // This prevents the previous preset from briefly playing
              if AudioManager.shared.soloModeSound != nil {
                AudioManager.shared.exitSoloModeWithoutResuming()
              }

              // Exit Quick Mix mode if active
              if AudioManager.shared.isQuickMix {
                AudioManager.shared.exitQuickMix()
              }
            }

            try await PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            print("🚗 CarPlay: Error applying preset: \(error)")
          }
          completion()
        }
      }

      return item
    }

    private static func getPresetDetailText(_ preset: Preset) -> String {
      let activeSounds = preset.soundStates.filter { $0.isSelected }

      var detailParts: [String] = []

      // Add creator name first if available
      if let creator = preset.creatorName, !creator.isEmpty {
        detailParts.append(creator)
      }

      // Add sound names
      if activeSounds.isEmpty {
        if detailParts.isEmpty {
          return "No active sounds"
        }
      } else {
        let soundNames = activeSounds.compactMap { soundState in
          AudioManager.shared.sounds.first { $0.fileName == soundState.fileName }?.title
        }

        if !soundNames.isEmpty {
          let soundsList = soundNames.joined(separator: ", ")
          detailParts.append(soundsList)
        }
      }

      // Join all parts with a separator
      return detailParts.joined(separator: " • ")
    }

    private static func getPresetArtwork(_ preset: Preset) -> UIImage? {
      // Check if we have a cached thumbnail for this preset
      let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"

      // Use app group UserDefaults for sharing between app and CarPlay
      let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard

      if let thumbnailData = userDefaults.data(forKey: thumbnailKey),
        let image = UIImage(data: thumbnailData)
      {
        return image
      }

      // For CarPlay, we rely on pre-cached thumbnails from the main app
      // Thumbnails should be cached by the main app when presets are created/modified

      // Return nil if no cached thumbnail is available
      return nil
    }

    private static func addRecentSection(to sections: inout [CPListSection]) {
      if let currentPreset = PresetManager.shared.currentPreset,
        !currentPreset.isDefault
      {
        let recentItem = createPresetListItem(currentPreset)
        sections.append(
          CPListSection(
            items: [recentItem],
            header: "Recent",
            sectionIndexTitle: "R"
          )
        )
      }
    }

    private static func addCustomPresetsSection(
      to sections: inout [CPListSection], customPresets: [Preset]
    ) {
      let allItems = customPresets.map { createPresetListItem($0) }
      sections.append(
        CPListSection(
          items: allItems,
          header: "All Presets",
          sectionIndexTitle: "A"
        )
      )
    }

    private static func addAllSoundsSection(
      to sections: inout [CPListSection], defaultPreset: Preset?
    ) {
      if let defaultPreset = defaultPreset {
        let allSoundsItem = createAllSoundsItem(defaultPreset)
        sections.append(
          CPListSection(
            items: [allSoundsItem],
            header: nil,
            sectionIndexTitle: nil
          )
        )
      }
    }

    private static func addEmptyStateSection(
      to sections: inout [CPListSection], defaultPreset: Preset?
    ) {
      if let defaultPreset = defaultPreset {
        let allSoundsItem = createAllSoundsItem(defaultPreset)
        sections.append(
          CPListSection(
            items: [allSoundsItem],
            header: "Presets",
            sectionIndexTitle: "P"
          )
        )
      }

      let emptyItem = CPListItem(
        text: "Create presets in iPhone app",
        detailText: "Your saved presets will appear here"
      )
      emptyItem.isEnabled = false
      sections.append(
        CPListSection(items: [emptyItem])
      )
    }

    private static func createAllSoundsItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: isActive ? "Custom Mix ✓" : "Custom Mix",
        detailText: "Current selections in \"All Blankie Sounds\"",
        image: getPresetArtwork(preset)
      )

      if isActive {
        item.accessoryType = .disclosureIndicator
      }

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Exit solo mode without resuming previous sounds if active
              // This prevents the previous preset from briefly playing
              if AudioManager.shared.soloModeSound != nil {
                AudioManager.shared.exitSoloModeWithoutResuming()
              }

              // Exit Quick Mix mode if active
              if AudioManager.shared.isQuickMix {
                AudioManager.shared.exitQuickMix()
              }
            }

            try await PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Ensure playback starts
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            print("🚗 CarPlay: Error applying All Sounds preset: \(error)")
          }
          completion()
        }
      }

      return item
    }
  }

#endif
