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
        debugLog("SoundsListTemplate: No sounds loaded yet", .carPlay)
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

// MARK: - Image Rendering

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  extension SoundsListTemplate {
    static func getSoundImage(for sound: Sound) -> UIImage? {
      // Create a circular background with the icon centered
      let size = CGSize(width: 40, height: 40)
      let renderer = UIGraphicsImageRenderer(size: size)

      return renderer.image { _ in
        let isInSoloMode = AudioManager.shared.soloModeSound?.id == sound.id

        drawBackground(size: size, isInSoloMode: isInSoloMode, sound: sound)
        drawIcon(size: size, isInSoloMode: isInSoloMode, sound: sound)
      }
    }

    private static func drawBackground(size: CGSize, isInSoloMode: Bool, sound: Sound) {
      let backgroundColor = getBackgroundColor(for: sound, isInSoloMode: isInSoloMode)

      if isInSoloMode {
        // Show colored background when playing
        backgroundColor.withAlphaComponent(0.3).setFill()
      } else {
        // Very subtle gray background when not playing
        UIColor.systemGray.withAlphaComponent(0.1).setFill()
      }

      let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
      circle.fill()
    }

    private static func drawIcon(size: CGSize, isInSoloMode: Bool, sound: Sound) {
      // Draw icon
      let iconName = sound.systemIconName
      let icon = UIImage(systemName: iconName) ?? UIImage(systemName: "speaker.wave.2")!

      // Configure icon size proportionally
      let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
      let configuredIcon = icon.withConfiguration(iconConfig)

      let iconSize = CGSize(width: 28, height: 28)
      let iconRect = CGRect(
        x: (size.width - iconSize.width) / 2,
        y: (size.height - iconSize.height) / 2,
        width: iconSize.width,
        height: iconSize.height
      )

      // Set icon color based on state and customization
      if isInSoloMode {
        getBackgroundColor(for: sound, isInSoloMode: isInSoloMode).setFill()
      } else {
        UIColor.carPlayIconTint.setFill()
      }
      configuredIcon.withRenderingMode(.alwaysTemplate).draw(in: iconRect)
    }

    private static func getBackgroundColor(for sound: Sound, isInSoloMode: Bool) -> UIColor {
      if isInSoloMode {
        // Use the same color hierarchy as the main app
        return UIColor.carPlayIconTint
      } else {
        return UIColor.systemGray
      }
    }
  }

  extension UIColor {
    /// Tint for CarPlay sound icons: the user's accent color, falling back to system tint.
    static var carPlayIconTint: UIColor {
      if let themeColor = GlobalSettings.shared.customAccentColor {
        return UIColor(themeColor)
      }
      return UIColor.tintColor
    }
  }

#endif
