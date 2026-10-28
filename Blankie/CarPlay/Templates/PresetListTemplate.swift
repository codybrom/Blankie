//
// PresetListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  enum PresetListTemplate {
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(
        title: String(localized: "Presets"),
        sections: []
      )

      template.tabImage = UIImage(systemName: "list.bullet")

      updateTemplate(template)
      return template
    }

    static func updateTemplate(_ template: CPListTemplate) {
      guard !PresetManager.shared.isLoading else {
        Logger.carPlay.debug(
          "PresetListTemplate: PresetManager still loading, showing loading state")
        let loadingItem = CPListItem(text: String(localized: "Loading presets..."), detailText: nil)
        let section = CPListSection(items: [loadingItem])
        template.updateSections([section])
        return
      }

      let customPresets = PresetManager.shared.presets.filter { !$0.isDefault }
      let defaultPreset = PresetManager.shared.presets.first { $0.isDefault }

      // The full browse list: every preset plus All Sounds. Recent and Favorites
      // are on the Home tab, so nothing is deduplicated.
      var sections: [CPListSection] = []

      if customPresets.isEmpty {
        addEmptyStateSection(to: &sections, defaultPreset: defaultPreset)
      } else {
        // All Blankie Sounds stays on top, as in the app. Named presets follow
        // alphabetically.
        addAllSoundsSection(to: &sections, defaultPreset: defaultPreset)
        addCustomPresetsSection(to: &sections, customPresets: customPresets)
      }

      template.updateSections(sections)
    }

    // Row builders shared with HomeListTemplate, so they're internal.
    static func createPresetListItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: preset.name,
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      // Leading "now playing" indicator marks the active item while it plays.
      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive && AudioManager.shared.isGloballyPlaying

      item.handler = { _, completion in
        playPresetFromCar(preset, completion: completion)
      }

      return item
    }

    private static func createCurrentSoundscapeItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: String(localized: "Current Soundscape"),
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive && AudioManager.shared.isGloballyPlaying

      item.handler = { _, completion in
        playPresetFromCar(preset, completion: completion)
      }

      return item
    }

    /// Applies a preset row tapped in the car. Drops the tap if the car went away
    /// before it ran, and re-reads the preset by id since the row may predate a
    /// phone-side edit or delete.
    private static func playPresetFromCar(_ preset: Preset, completion: @escaping () -> Void) {
      Task {
        do {
          let livePreset = await MainActor.run { () -> Preset? in
            guard CarPlayInterfaceController.shared.isConnected else { return nil }
            return PresetManager.shared.presets.first { $0.id == preset.id }
          }
          guard let livePreset else {
            Logger.carPlay.debug("CarPlay: Dropped a preset tap (car gone or preset deleted)")
            await MainActor.run { CarPlayInterfaceController.shared.updateAllTemplates() }
            return completion()
          }

          try await MainActor.run {
            try PresetManager.shared.playPreset(livePreset)
            CarPlayInterfaceController.shared.updateAllTemplates()
            CarPlayInterfaceController.shared.showNowPlaying()
          }
        } catch {
          Logger.carPlay.error("CarPlay: Error applying preset: \(error, privacy: .public)")
        }
        completion()
      }
    }

    private static func getPresetDetailText(_ preset: Preset) -> String {
      let activeSounds = preset.soundStates.filter { $0.isSelected }

      var detailParts: [String] = []

      if let creator = preset.creatorName, !creator.isEmpty {
        detailParts.append(creator)
      }

      if activeSounds.isEmpty {
        if detailParts.isEmpty {
          return String(localized: "No active sounds")
        }
      } else {
        let sounds = activeSounds.compactMap { soundState in
          AudioManager.shared.sounds.first { $0.fileName == soundState.fileName }
        }

        if !sounds.isEmpty {
          detailParts.append(CarPlaySoundNames.list(sounds))
        }
      }

      return detailParts.joined(separator: " • ")
    }

    private static func getPresetArtwork(_ preset: Preset) -> UIImage? {
      // The app caches a thumbnail of custom or animated artwork whenever a
      // preset is created or modified.
      let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"
      let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard

      if let thumbnailData = userDefaults.data(forKey: thumbnailKey),
        let image = UIImage(data: thumbnailData)
      {
        return image
      }

      // Otherwise render the library's FallbackArtwork. CarPlay templates are
      // always built on the main thread.
      return MainActor.assumeIsolated { fallbackArtwork(for: preset) }
    }

    /// Rasterize the shared `FallbackArtwork` for a preset with no custom or
    /// animated artwork, matching its in-app library tile.
    @MainActor
    private static func fallbackArtwork(for preset: Preset) -> UIImage? {
      let accent = preset.accentColor ?? GlobalSettings.shared.customAccentColor ?? .accentColor

      let glyph: FallbackArtwork.Glyph
      let glyphFraction: CGFloat
      if preset.isDefault {
        glyph = .brand
        glyphFraction = 0.5
      } else {
        let icons = AudioManager.shared.compositeSoundIcons(for: preset)
        glyph = icons.isEmpty ? .symbol("music.note") : .composite(icons)
        glyphFraction = 0.44
      }

      // Fill the list image slot (per car, read at runtime) at the car
      // display's scale, matching how the system scales cached thumbnails.
      let slot = CPListItem.maximumImageSize
      let view = FallbackArtwork(
        glyph: glyph,
        accent: accent,
        size: min(slot.width, slot.height),
        cornerRadius: 0,
        glyphFraction: glyphFraction
      )
      let renderer = ImageRenderer(content: view)
      renderer.scale = CarPlayInterfaceController.shared.carDisplayScale
      renderer.isOpaque = true
      return renderer.uiImage
    }

    private static func addCustomPresetsSection(
      to sections: inout [CPListSection], customPresets: [Preset]
    ) {
      // One headerless section per first letter so CarPlay's index can jump by
      // letter. "#" (names that don't start with a letter) sorts last.
      let sorted = customPresets.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      let groups = Dictionary(grouping: sorted) { sectionIndexLetter(for: $0.name) }
      let letters = groups.keys.sorted { a, b in
        if a == "#" { return false }
        if b == "#" { return true }
        return a < b
      }
      for letter in letters {
        let items = (groups[letter] ?? []).map { createPresetListItem($0) }
        sections.append(
          CPListSection(items: items, header: nil, sectionIndexTitle: letter)
        )
      }
    }

    /// First letter of a preset name for the section index, or "#" for names that
    /// don't start with a Latin letter (numbers, symbols, other scripts).
    private static func sectionIndexLetter(for name: String) -> String {
      guard let first = name.first(where: { !$0.isWhitespace }) else { return "#" }
      let upper = String(first).uppercased()
      return upper.range(of: "^[A-Z]$", options: .regularExpression) != nil ? upper : "#"
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
            header: String(localized: "Presets"),
            sectionIndexTitle: "P"
          )
        )
      }

      let emptyItem = CPListItem(
        text: String(localized: "Create presets in iPhone app"),
        detailText: String(localized: "Your saved presets will appear here")
      )
      emptyItem.isEnabled = false
      sections.append(
        CPListSection(items: [emptyItem])
      )
    }

    // A starred sound row. Selecting it plays the sound on its own. `@MainActor` for
    // the `creditedAuthor` lookup.
    @MainActor
    static func createSingleItem(_ sound: Sound) -> CPListItem {
      let isActive = AudioManager.shared.singleSound?.id == sound.id

      // Caption only a custom sound that credits an artist. Built-in authors are
      // in the credits screens.
      let item = CPListItem(
        text: sound.localizedTitle,
        detailText: sound.isCustom ? sound.creditedAuthor : nil,
        image: SoundsListTemplate.getSoundImage(for: sound)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive && AudioManager.shared.isGloballyPlaying

      item.handler = { _, completion in
        Task {
          await MainActor.run { SoundsListTemplate.playSingleSound(sound) }
          completion()
        }
      }

      return item
    }

    static func createAllSoundsItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      // Styled like any other preset row, with its active sounds underneath.
      let item = CPListItem(
        text: preset.displayName,
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive && AudioManager.shared.isGloballyPlaying

      item.handler = { _, completion in
        playPresetFromCar(preset, completion: completion)
      }

      return item
    }
  }

#endif
