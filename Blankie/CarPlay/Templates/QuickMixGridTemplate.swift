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

      template.tabImage = UIImage(systemName: "square.grid.2x2")

      return template
    }

    static func updateTemplate(_ template: CPGridTemplate) {
      guard !AudioManager.shared.sounds.isEmpty else {
        Logger.carPlay.debug("QuickMixGridTemplate: No sounds loaded yet")
        return
      }

      let updatedButtons = createGridButtons()
      template.updateGridButtons(updatedButtons)
    }

    private static func createGridButtons() -> [CPGridButton] {
      let quickMixSounds = CarPlayInterfaceController.shared.quickMixSoundFileNames

      return quickMixSounds.compactMap { fileName in
        // Preset-use-only sounds can't play alone, so skip them even when an
        // older saved set lists them.
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
      // Use the logical playback state. A sound just toggled off may still be
      // rendering its fade-out when this refreshes.
      let isPlaying =
        sound.playbackState == .playing && AudioManager.shared.isQuickMix
        && AudioManager.shared.singleSound == nil

      let titles = [CarPlaySoundNames.name(of: sound)]

      let button = CPGridButton(
        titleVariants: titles,
        image: getButtonImage(for: sound, isPlaying: isPlaying)
      ) { button in
        handleSoundToggle(sound, button: button)
      }

      return button
    }

    private static func getButtonImage(for sound: Sound, isPlaying: Bool) -> UIImage {
      // Render at CarPlay's grid-button size and the car display's scale so the icon is crisp.
      let size = CPGridTemplate.maximumGridButtonImageSize
      let format = UIGraphicsImageRendererFormat()
      format.scale = CarPlayInterfaceController.shared.carDisplayScale
      let renderer = UIGraphicsImageRenderer(size: size, format: format)

      return renderer.image { _ in
        let backgroundColor = getBackgroundColor(for: sound, isPlaying: isPlaying)

        backgroundColor.withAlphaComponent(isPlaying ? 0.3 : 0.2).setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

        // Centered icon at the 100pt button's proportions (50pt box, 36pt symbol).
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
      guard isPlaying else {
        return UIColor.systemGray
      }

      return UIColor.carPlayIconTint
    }

    private static func handleSoundToggle(_ sound: Sound, button _: CPGridButton) {
      Task { @MainActor in
        // The car may have disconnected before this tap ran. Never start on the phone.
        guard CarPlayInterfaceController.shared.isConnected else { return }

        if AudioManager.shared.singleSound != nil {
          AudioManager.shared.exitSingleSoundWithoutResuming()
        }

        if !AudioManager.shared.isQuickMix {
          AudioManager.shared.enterQuickMix(with: [sound])
        } else {
          AudioManager.shared.toggleQuickMixSound(sound)
        }

        CarPlayInterfaceController.shared.updateAllTemplates()

        NotificationCenter.default.post(name: .soundStateChanged, object: sound)
      }
    }
  }

#endif
