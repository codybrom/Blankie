//
//  PresetEditTemplate.swift
//  Blankie
//
//  Created by Cody Bromley on 12/21/24.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  enum PresetEditTemplate {
    // MARK: - Main Edit Template

    static func createTemplate() -> CPListTemplate {
      // The app's display name for the preset ("All Blankie Sounds" for the default).
      let presetName =
        PresetManager.shared.currentPreset?.displayName ?? String(localized: "Current Mix")

      let template = CPListTemplate(
        title: presetName,
        sections: []
      )

      updateTemplate(template)
      return template
    }

    static func updateTemplate(_ template: CPListTemplate) {
      guard let currentPreset = PresetManager.shared.currentPreset else {
        let noPresetItem = CPListItem(
          text: String(localized: "No preset selected"), detailText: nil)
        let section = CPListSection(items: [noPresetItem])
        template.updateSections([section])
        return
      }

      let presetSounds = AudioManager.shared.sounds.filter { sound in
        // Includes preset sounds that are turned off.
        currentPreset.soundStates.contains { $0.fileName == sound.fileName }
      }

      guard !presetSounds.isEmpty else {
        let emptySoundsItem = CPListItem(
          text: String(localized: "No sounds in this preset"), detailText: nil)
        let section = CPListSection(items: [emptySoundsItem])
        template.updateSections([section])
        return
      }

      let sortedSounds = CarPlaySoundNames.sorted(presetSounds)

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

    /// Edits apply to the live mix of the preset the stack was opened for. A tap
    /// that lands after a switch, single sound or Quick Mix dismisses the stack instead.
    @MainActor
    private static func editsLiveMix() -> Bool {
      guard CarPlayInterfaceController.shared.editStackIsLive else {
        CarPlayInterfaceController.shared.dismissEditStack()
        return false
      }
      return true
    }

    private static func createSoundEditItem(_ sound: Sound) -> CPListItem {
      let isSelected = sound.isSelected
      let percent = Double(sound.volume).formatted(.percent.precision(.fractionLength(0)))
      let volumeText = String(localized: "\(percent) Volume")

      let item = CPListItem(
        text: CarPlaySoundNames.name(of: sound),
        detailText: isSelected
          ? String(localized: "Playing • \(volumeText)") : String(localized: "Stopped")
      )

      if let image = createSoundIcon(for: sound, isPlaying: isSelected) {
        item.setImage(image)
      }

      item.accessoryType = .disclosureIndicator

      item.handler = { _, completion in
        Task { @MainActor in
          if sound.isSelected {
            CarPlayInterfaceController.shared.showVolumeAdjustment(for: sound)
          } else {
            CarPlayInterfaceController.shared.showTurnOnOptions(for: sound)
          }

          completion()
        }
      }

      return item
    }

    private static func createSoundIcon(for sound: Sound, isPlaying: Bool) -> UIImage? {
      let size = CGSize(width: 40, height: 40)
      let renderer = UIGraphicsImageRenderer(size: size)

      return renderer.image { _ in
        let soundColor = UIColor.carPlayIconTint

        if isPlaying {
          soundColor.withAlphaComponent(0.3).setFill()
          let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
          circle.fill()
        }

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

        let iconColor: UIColor
        if isPlaying {
          iconColor = soundColor
        } else {
          iconColor = UIColor.systemGray
        }

        let coloredIcon = configuredIcon.withTintColor(iconColor, renderingMode: .alwaysOriginal)
        coloredIcon.draw(in: iconRect)
      }
    }

    // MARK: - Volume Adjustment Template

    static func createVolumeAdjustmentTemplate(for sound: Sound) -> CPListTemplate {
      let template = CPListTemplate(
        title: String(localized: "\(CarPlaySoundNames.name(of: sound)) Volume"),
        sections: []
      )

      var items: [CPListItem] = []

      items.append(createCurrentVolumeItem(for: sound))

      items.append(createTurnOffItem(for: sound))

      items.append(contentsOf: createVolumeItems(for: sound))

      let section = CPListSection(items: items)
      template.updateSections([section])

      return template
    }

    private static func createCurrentVolumeItem(for sound: Sound) -> CPListItem {
      let percent = Double(sound.volume).formatted(.percent.precision(.fractionLength(0)))
      let item = CPListItem(
        text: String(localized: "\(percent) Volume"),
        detailText: nil
      )
      item.isEnabled = false
      return item
    }

    private static func createTurnOffItem(for sound: Sound) -> CPListItem {
      let item = CPListItem(
        text: String(localized: "Stop"),
        detailText: String(localized: "Turn off this sound")
      )
      item.handler = { _, completion in
        Task { @MainActor in
          guard editsLiveMix() else { return completion() }
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
          text: (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0))),
          detailText: isCurrentVolume ? String(localized: "Current") : nil
        )

        if isCurrentVolume {
          item.isEnabled = false
          item.handler = nil
        } else {
          item.handler = { _, completion in
            Task { @MainActor in
              guard editsLiveMix() else { return completion() }
              sound.volume = volume
              AudioManager.shared.updateHasSelectedSounds()
              PresetManager.shared.savePresets()
              CarPlayInterfaceController.shared.popAndRefreshEditTemplate()
              completion()
            }
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

      let headerItem = CPListItem(
        text: String(localized: "Choose a volume to start \(CarPlaySoundNames.name(of: sound))"),
        detailText: nil
      )
      headerItem.isEnabled = false
      items.append(headerItem)

      for percentage in stride(from: 100, through: 10, by: -10) {
        let volume = Float(percentage) / 100.0

        let item = CPListItem(
          text: (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0))),
          detailText: nil
        )

        item.handler = { _, completion in
          Task { @MainActor in
            guard editsLiveMix() else { return completion() }
            // Selecting auto-plays while playback is active, so no direct play().
            sound.volume = volume
            sound.isSelected = true

            AudioManager.shared.updateHasSelectedSounds()

            PresetManager.shared.savePresets()

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
