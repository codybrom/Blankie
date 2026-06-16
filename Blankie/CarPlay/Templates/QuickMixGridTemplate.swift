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
        title: String(localized: "Quick Mix"),
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
        // Preset-use-only sounds can't stand alone, so they never appear as a
        // Quick Mix button even if an old saved set still lists them.
        guard
          let sound = AudioManager.shared.sounds.first(where: {
            $0.fileName == fileName && !$0.isPresetUseOnly
          })
        else {
          return nil
        }

        return createGridButton(for: sound)
      }
    }

    private static func createGridButton(for sound: Sound) -> CPGridButton {
      // Check if sound is currently playing in QuickMix mode. Use logical
      // playback state, not the node: a just-toggled-off sound is still
      // rendering its fade-out when this template refreshes.
      let isPlaying =
        sound.playbackState == .playing && AudioManager.shared.isQuickMix
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
      // Render at CarPlay's expected grid-button size and the car display's pixel
      // scale, so the icon is crisp instead of being upscaled from a fixed bitmap.
      let size = CPGridTemplate.maximumGridButtonImageSize
      let format = UIGraphicsImageRendererFormat()
      format.scale = CarPlayInterfaceController.shared.carDisplayScale
      let renderer = UIGraphicsImageRenderer(size: size, format: format)

      return renderer.image { _ in
        let backgroundColor = getBackgroundColor(for: sound, isPlaying: isPlaying)

        // Circle background filling the button (matching the Blankie app).
        backgroundColor.withAlphaComponent(isPlaying ? 0.3 : 0.2).setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

        // Centered icon, proportions preserved from the previous 100pt button
        // (50pt icon box, 36pt symbol).
        let icon =
          UIImage(systemName: sound.systemIconName) ?? UIImage(systemName: "speaker.wave.2")!
        let configuredIcon = icon.withConfiguration(
          UIImage.SymbolConfiguration(pointSize: size.width * 0.36, weight: .medium))

        let iconSide = size.width * 0.5
        let iconRect = CGRect(
          x: (size.width - iconSide) / 2,
          y: (size.height - iconSide) / 2,
          width: iconSide,
          height: iconSide
        )

        (isPlaying ? backgroundColor : UIColor.systemGray).setFill()
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
