//
// SoundsListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  enum SoundsListTemplate {
    @MainActor
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(
        title: String(localized: "Sounds"),
        sections: []
      )

      template.tabImage = UIImage(systemName: "speaker.wave.2")

      updateTemplate(template)
      return template
    }

    @MainActor
    static func updateTemplate(_ template: CPListTemplate) {
      guard !AudioManager.shared.sounds.isEmpty else {
        Logger.carPlay.debug("SoundsListTemplate: No sounds loaded yet")
        let loadingItem = CPListItem(text: String(localized: "Loading sounds..."), detailText: nil)
        let section = CPListSection(items: [loadingItem])
        template.updateSections([section])
        return
      }

      var sections: [CPListSection] = []

      // Preset-use-only sounds (explicit, or implied by a non-looping one-shot)
      // can't play alone, so they're hidden here as in the app.
      let allSounds =
        AudioManager.shared.sounds
        .filter { !$0.isPresetUseOnly }
        .sorted { $0.title < $1.title }

      // One section per first letter for CarPlay's index.
      let groupedSounds = Dictionary(grouping: allSounds) { sound in
        String(sound.title.prefix(1).uppercased())
      }

      let sortedKeys = groupedSounds.keys.sorted()
      for key in sortedKeys {
        if let sounds = groupedSounds[key] {
          let soundItems = sounds.map { createSoundListItem($0) }
          sections.append(
            CPListSection(
              items: soundItems,
              header: nil,
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

      if isInSoloMode {
        item.accessoryType = .disclosureIndicator
        item.setText("\(sound.title) ✓")
      }

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

    /// Solos a sound tapped in the car. The preset list's solo rows share it.
    @MainActor
    static func playSoundInSoloMode(_ sound: Sound) {
      // The car may have disconnected before this tap ran. Never start on the phone.
      guard CarPlayInterfaceController.shared.isConnected else { return }

      // A stale row can't solo a sound that was deleted or became preset-use-only
      // (the same rule the intents follow).
      guard AudioManager.shared.sounds.contains(where: { $0 === sound }), !sound.isPresetUseOnly
      else {
        CarPlayInterfaceController.shared.updateAllTemplates()
        return
      }

      if AudioManager.shared.soloModeSound?.id == sound.id {
        CarPlayInterfaceController.shared.showNowPlaying()
      } else {
        AudioManager.shared.enterSoloMode(for: sound)
        CarPlayInterfaceController.shared.showNowPlaying()
      }

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
        backgroundColor.withAlphaComponent(0.3).setFill()
      } else {
        UIColor.systemGray.withAlphaComponent(0.1).setFill()
      }

      let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
      circle.fill()
    }

    private static func drawIcon(size: CGSize, isInSoloMode: Bool, sound: Sound) {
      let iconName = sound.systemIconName
      let icon = UIImage(systemName: iconName) ?? UIImage(systemName: "speaker.wave.2")!

      let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
      let configuredIcon = icon.withConfiguration(iconConfig)

      let iconSize = CGSize(width: 28, height: 28)
      let iconRect = CGRect(
        x: (size.width - iconSize.width) / 2,
        y: (size.height - iconSize.height) / 2,
        width: iconSize.width,
        height: iconSize.height
      )

      if isInSoloMode {
        getBackgroundColor(for: sound, isInSoloMode: isInSoloMode).setFill()
      } else {
        UIColor.carPlayIconTint.setFill()
      }
      configuredIcon.withRenderingMode(.alwaysTemplate).draw(in: iconRect)
    }

    private static func getBackgroundColor(for sound: Sound, isInSoloMode: Bool) -> UIColor {
      if isInSoloMode {
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
