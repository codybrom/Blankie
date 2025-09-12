//
// SoundsListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

#if CARPLAY_ENABLED

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
        print("🚗 SoundsListTemplate: No sounds loaded yet")
        let loadingItem = CPListItem(text: "Loading sounds...", detailText: nil)
        let section = CPListSection(items: [loadingItem])
        template.updateSections([section])
        return
      }

      // Load custom sounds lazily when CarPlay UI is actually being used
      AudioManager.shared.loadCustomSoundsLazily()

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
      // Toggle solo mode for this sound
      AudioManager.shared.toggleSoloMode(for: sound)

      // Update interface
      CarPlayInterfaceController.shared.updateAllTemplates()

      // Show Now Playing if we started playing
      if AudioManager.shared.soloModeSound != nil {
        CarPlayInterfaceController.shared.showNowPlaying()
      }
    }
  }

#endif
