//
// HomeListTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/12/26.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  /// CarPlay landing tab: the live mix (or the most recent preset), then favorites.
  /// Rows reuse PresetListTemplate's shared builders.
  enum HomeListTemplate {
    @MainActor
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(
        title: String(
          localized: "carplay.tab.home", defaultValue: "Home",
          comment: "CarPlay landing-tab title for the home/main screen of the app"),
        sections: [])
      template.tabImage = UIImage(systemName: "house.fill")
      updateTemplate(template)
      return template
    }

    @MainActor
    static func updateTemplate(_ template: CPListTemplate) {
      guard !PresetManager.shared.isLoading else {
        let loading = CPListItem(text: String(localized: "Loading..."), detailText: nil)
        template.updateSections([CPListSection(items: [loading])])
        return
      }

      var sections: [CPListSection] = []
      if let nowPlaying = nowPlayingSection() { sections.append(nowPlaying) }
      if let favorites = favoritesSection() { sections.append(favorites) }

      if sections.isEmpty {
        let empty = CPListItem(
          text: String(localized: "Nothing playing yet"),
          detailText: String(localized: "Pick a preset or sound to get started")
        )
        empty.isEnabled = false
        sections.append(CPListSection(items: [empty]))
      }

      template.updateSections(sections)
    }

    /// The current mix (single sound, Quick Mix or a preset), or the most recent preset when
    /// nothing is active. The header reads "Now Playing" while playing, else "Recent".
    @MainActor
    private static func nowPlayingSection() -> CPListSection? {
      let header =
        AudioManager.shared.isGloballyPlaying
        ? String(localized: "Now Playing") : String(localized: "Recent")

      let item: CPListItem
      if let single = AudioManager.shared.singleSound {
        item = PresetListTemplate.createSingleItem(single)
      } else if AudioManager.shared.isQuickMix {
        item = quickMixItem()
      } else if let preset = PresetManager.shared.currentPreset {
        if preset.isDefault {
          // Show the default mix only when something in it is selected.
          guard AudioManager.shared.hasSelectedSounds else { return nil }
          item = PresetListTemplate.createAllSoundsItem(preset)
        } else {
          item = PresetListTemplate.createPresetListItem(preset)
        }
      } else {
        return nil
      }

      return CPListSection(items: [item], header: header, sectionIndexTitle: nil)
    }

    /// Quick Mix row for the Now Playing section. Tapping opens the Now Playing screen.
    private static func quickMixItem() -> CPListItem {
      let selected = AudioManager.shared.sounds.filter { $0.isSelected }
      let item = CPListItem(
        text: String(localized: "Quick Mix"),
        detailText: selected.isEmpty ? nil : CarPlaySoundNames.list(selected)
      )
      item.playingIndicatorLocation = .leading
      item.isPlaying = AudioManager.shared.isGloballyPlaying
      item.handler = { _, completion in
        Task { @MainActor in
          CarPlayInterfaceController.shared.showNowPlaying()
          completion()
        }
      }
      return item
    }

    /// Starred items in saved order, from the `GlobalSettings.starredItems` list the
    /// iPad sidebar also uses.
    @MainActor
    private static func favoritesSection() -> CPListSection? {
      let presets = PresetManager.shared.presets
      let items: [CPListItem] = GlobalSettings.shared.starredItems.compactMap { token in
        switch PlayableItem(token: token) {
        case .single(let fileName):
          guard let sound = AudioManager.shared.sound(fileName: fileName) else { return nil }
          return PresetListTemplate.createSingleItem(sound)
        case .allSounds:
          guard let defaultPreset = presets.first(where: { $0.isDefault }) else { return nil }
          return PresetListTemplate.createAllSoundsItem(defaultPreset)
        case .quickMix:
          // Quick Mix has its own tab, so its token is skipped here.
          return nil
        case .preset(let id):
          guard let preset = presets.first(where: { $0.id == id }) else { return nil }
          return PresetListTemplate.createPresetListItem(preset)
        case .none:
          return nil
        }
      }

      guard !items.isEmpty else { return nil }

      return CPListSection(
        items: items,
        header: String(localized: "Favorites"),
        sectionIndexTitle: "F"
      )
    }
  }

#endif
