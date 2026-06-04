//
// QuickMixGridTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  enum QuickMixGridTemplate {
    static func createTemplate() -> CPGridTemplate {
      let gridButtons = createGridButtons()

      let template = CPGridTemplate(
        title: "Quick Mix",
        gridButtons: gridButtons
      )

      // Set tab image
      template.tabImage = UIImage(systemName: "square.grid.2x2")

      return template
    }

    static func updateTemplate(_ template: CPGridTemplate) {
      // Safety check for initialization
      guard !AudioManager.shared.sounds.isEmpty else {
        Logger.carPlay.debug("QuickMixGridTemplate: No sounds loaded yet")
        return
      }

      // Update grid buttons with current state
      let updatedButtons = createGridButtons()
      template.updateGridButtons(updatedButtons)
    }

    private static func createGridButtons() -> [CPGridButton] {
      let quickMixSounds = CarPlayInterfaceController.shared.quickMixSoundFileNames

      return quickMixSounds.compactMap { fileName in
        guard let sound = AudioManager.shared.sounds.first(where: { $0.fileName == fileName })
        else {
          return nil
        }

        return createGridButton(for: sound)
      }
    }

    private static func createGridButton(for sound: Sound) -> CPGridButton {
      // Check if sound is currently playing in QuickMix mode
      let isPlaying =
        sound.player?.isPlaying == true && AudioManager.shared.isQuickMix
        && AudioManager.shared.soloModeSound == nil

      // Create button titles
      let titles = [sound.title]

      // Create button with system image for now
      let button = CPGridButton(
        titleVariants: titles,
        image: getButtonImage(for: sound, isPlaying: isPlaying)
      ) { button in
        handleSoundToggle(sound, button: button)
      }

      return button
    }

    private static func getButtonImage(for sound: Sound, isPlaying: Bool) -> UIImage {
      // Create a colored circle background with the icon
      let size = CGSize(width: 100, height: 100)
      let renderer = UIGraphicsImageRenderer(size: size)

      return renderer.image { _ in
        // Get the color for this sound
        let backgroundColor = getBackgroundColor(for: sound, isPlaying: isPlaying)

        // Draw the circle background with opacity (matching Blankie app)
        backgroundColor.withAlphaComponent(isPlaying ? 0.3 : 0.2).setFill()
        let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
        circle.fill()

        // Draw the icon in the center
        let iconName = sound.systemIconName
        let icon = UIImage(systemName: iconName) ?? UIImage(systemName: "speaker.wave.2")!

        // Use configuration for better icon rendering
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        let configuredIcon = icon.withConfiguration(iconConfig)

        let iconSize = CGSize(width: 50, height: 50)
        let iconRect = CGRect(
          x: (size.width - iconSize.width) / 2,
          y: (size.height - iconSize.height) / 2,
          width: iconSize.width,
          height: iconSize.height
        )

        if isPlaying {
          backgroundColor.setFill()
        } else {
          UIColor.systemGray.setFill()
        }
        configuredIcon.withRenderingMode(.alwaysTemplate).draw(in: iconRect)
      }
    }

    private static func getBackgroundColor(for sound: Sound, isPlaying: Bool) -> UIColor {
      // When not playing, use gray
      guard isPlaying else {
        return UIColor.systemGray
      }

      // When playing, use the same color hierarchy
      return UIColor.carPlayIconTint
    }

    private static func handleSoundToggle(_ sound: Sound, button _: CPGridButton) {
      Task { @MainActor in
        // Exit solo mode if active
        if AudioManager.shared.soloModeSound != nil {
          AudioManager.shared.exitSoloModeWithoutResuming()
        }

        // Check if we're in CarPlay Quick Mix mode
        if !AudioManager.shared.isQuickMix {
          // Enter Quick Mix mode with this sound
          AudioManager.shared.enterQuickMix(with: [sound])
        } else {
          // We're already in Quick Mix, toggle this specific sound
          AudioManager.shared.toggleQuickMixSound(sound)
        }

        // Update the interface
        CarPlayInterfaceController.shared.updateAllTemplates()

        // Post notification for other parts of the app
        NotificationCenter.default.post(name: .soundStateChanged, object: sound)
      }
    }
  }

#endif
