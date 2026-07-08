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

      // Set tab image
      template.tabImage = UIImage(systemName: "list.bullet")

      updateTemplate(template)
      return template
    }

    static func updateTemplate(_ template: CPListTemplate) {
      // Safety check for initialization
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

      // The Presets tab is the full browse list — every preset plus All Sounds.
      // Recent and Favorites live on the Home tab, so there's no dedup here.
      var sections: [CPListSection] = []

      if customPresets.isEmpty {
        addEmptyStateSection(to: &sections, defaultPreset: defaultPreset)
      } else {
        // All Blankie Sounds is a fixed row at the top (as in the in-app list);
        // the named presets follow, alphabetized with the A–Z scrubber.
        addAllSoundsSection(to: &sections, defaultPreset: defaultPreset)
        addCustomPresetsSection(to: &sections, customPresets: customPresets)
      }

      template.updateSections(sections)
    }

    // Shared row builders — also used by HomeListTemplate's Now Playing and
    // Favorites sections. Internal (not private) so Home can compose them.
    static func createPresetListItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      let item = CPListItem(
        text: preset.name,
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      // Leading "now playing" indicator marks the active item.
      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Leave solo/Quick Mix so the previous preset doesn't briefly play.
              AudioManager.shared.leaveTransientModes()
            }

            // Allow audio system to process mode exits before applying new preset
            await Task.yield()

            try PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Ensure playback starts
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            Logger.carPlay.error("CarPlay: Error applying preset: \(error, privacy: .public)")
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
        text: String(localized: "Current Soundscape"),
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Leave solo/Quick Mix so the previous preset doesn't briefly play.
              AudioManager.shared.leaveTransientModes()
            }

            // Allow audio system to process mode exits before applying new preset
            await Task.yield()

            try PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            Logger.carPlay.error("CarPlay: Error applying preset: \(error, privacy: .public)")
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
          return String(localized: "No active sounds")
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
      // Real (custom or animated) artwork is pre-rasterized into a cached
      // thumbnail by the main app whenever a preset is created or modified.
      let thumbnailKey = "preset_thumb_\(preset.id.uuidString)"
      let userDefaults = AppGroupConfiguration.sharedDefaults ?? UserDefaults.standard

      if let thumbnailData = userDefaults.data(forKey: thumbnailKey),
        let image = UIImage(data: thumbnailData)
      {
        return image
      }

      // No real artwork — render the same tinted FallbackArtwork the library
      // shows for this preset (the Blankie mark for "All Blankie Sounds", a
      // montage of its sounds otherwise) so CarPlay rows are never imageless.
      // CarPlay templates are always built on the main thread.
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

      // 44pt is the CarPlay list image footprint; render at 2x for crisp glyphs.
      let view = FallbackArtwork(
        glyph: glyph,
        accent: accent,
        size: 44,
        cornerRadius: 0,
        glyphFraction: glyphFraction
      )
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      renderer.isOpaque = true
      return renderer.uiImage
    }

    private static func addCustomPresetsSection(
      to sections: inout [CPListSection], customPresets: [Preset]
    ) {
      // Alphabetical, split into one section per first letter so CarPlay's A–Z
      // scrubber can jump by letter. No visible headers — the index rail is the
      // only affordance — and "#" (non-letter starts) sorts last, list-app style.
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

    /// First letter of a preset name for the A–Z index, or "#" for names that
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

    // Favorited solo sound — selecting it enters solo mode for that sound.
    // `@MainActor` for the `creditedAuthor` lookup.
    @MainActor
    static func createSoloItem(_ sound: Sound) -> CPListItem {
      let isActive = AudioManager.shared.soloModeSound?.id == sound.id

      // Caption only when a custom sound credits an artist; built-in authors live
      // in the credits screens. No generic "Custom sound" / "Solo sound" label.
      let item = CPListItem(
        text: sound.title,
        detailText: sound.isCustom ? sound.creditedAuthor : nil,
        image: SoundsListTemplate.getSoundImage(for: sound)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive

      item.handler = { _, completion in
        Task {
          await MainActor.run {
            AudioManager.shared.enterSoloMode(for: sound)
            CarPlayInterfaceController.shared.updateAllTemplates()
            CarPlayInterfaceController.shared.showNowPlaying()
          }
          completion()
        }
      }

      return item
    }

    static func createAllSoundsItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId

      // Named and styled like any other preset row — "All Blankie Sounds" with
      // its active sounds underneath, matching the in-app preset list.
      let item = CPListItem(
        text: preset.displayName,
        detailText: getPresetDetailText(preset),
        image: getPresetArtwork(preset)
      )

      item.playingIndicatorLocation = .leading
      item.isPlaying = isActive

      item.handler = { _, completion in
        Task {
          do {
            await MainActor.run {
              // Leave solo/Quick Mix so the previous preset doesn't briefly play.
              AudioManager.shared.leaveTransientModes()
            }

            // Allow audio system to process mode exits before applying new preset
            await Task.yield()

            try PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Ensure playback starts
              AudioManager.shared.setGlobalPlaybackState(true)
              CarPlayInterfaceController.shared.updateAllTemplates()
              // Navigate to Now Playing screen
              CarPlayInterfaceController.shared.showNowPlaying()
            }
          } catch {
            Logger.carPlay.error(
              "CarPlay: Error applying All Sounds preset: \(error, privacy: .public)")
          }
          completion()
        }
      }

      return item
    }
  }

#endif
