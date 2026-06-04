//
// SoundsListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  enum SoundsListTemplate {
    @MainActor
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(
        title: "Sounds",
        sections: []
      )

      // Set tab image
      template.tabImage = UIImage(systemName: "speaker.wave.2")

      updateTemplate(template)
      return template
    }

    @MainActor
    static func updateTemplate(_ template: CPListTemplate) {
      // Safety check for initialization
      guard !AudioManager.shared.sounds.isEmpty else {
        debugLog("SoundsListTemplate: No sounds loaded yet")
        let loadingItem = CPListItem(text: "Loading sounds...", detailText: nil)
        let section = CPListSection(items: [loadingItem])
        template.updateSections([section])
        return
      }

      // Custom sounds should already be loaded during app initialization

      var sections: [CPListSection] = []

      // Get all sounds and sort alphabetically
      let allSounds = AudioManager.shared.sounds.sorted { $0.title < $1.title }

      // Group sounds by first letter for better navigation
      let groupedSounds = Dictionary(grouping: allSounds) { sound in
        String(sound.title.prefix(1).uppercased())
      }

      // Create sections for each letter
      let sortedKeys = groupedSounds.keys.sorted()
      for key in sortedKeys {
        if let sounds = groupedSounds[key] {
          let soundItems = sounds.map { createSoundListItem($0) }
          sections.append(
            CPListSection(
              items: soundItems,
              header: nil,  // No header for cleaner look
              sectionIndexTitle: key
            )
          )
        }
      }

      template.updateSections(sections)
    }

    private static func createSoundListItem(_ sound: Sound) -> CPListItem {
      let isInSoloMode = AudioManager.shared.soloModeSound?.id == sound.id

      let item = CPListItem(
        text: sound.title,
        detailText: nil
      )

      // Add accessory if playing in solo mode
      if isInSoloMode {
        item.accessoryType = .disclosureIndicator
        item.setText("\(sound.title) ✓")
      }

      // Set image
      if let image = getSoundImage(for: sound) {
        item.setImage(image)
      }

      item.handler = { _, completion in
        Task { @MainActor in
          playSoundInSoloMode(sound)
          completion()
        }
      }

      return item
    }

    @MainActor
    private static func playSoundInSoloMode(_ sound: Sound) {
      // If this sound is already in solo mode, just show Now Playing
      if AudioManager.shared.soloModeSound?.id == sound.id {
        // Just navigate to Now Playing screen without changing playback
        CarPlayInterfaceController.shared.showNowPlaying()
      } else {
        // Switch to solo mode for a different sound
        AudioManager.shared.enterSoloMode(for: sound)
        // Show Now Playing when starting a new solo sound
        CarPlayInterfaceController.shared.showNowPlaying()
      }

      // Update interface
      CarPlayInterfaceController.shared.updateAllTemplates()
    }
  }

#endif
