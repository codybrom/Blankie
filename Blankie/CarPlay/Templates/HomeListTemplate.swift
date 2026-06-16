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

  /// CarPlay landing tab: the live mix (or the most recent preset) up top,
  /// followed by the user's favorites. Browsing all presets and sounds lives in
  /// the Presets and Sounds tabs — Home is the fast path back to a current or
  /// pinned mix. Rows reuse PresetListTemplate's shared builders.
  enum HomeListTemplate {
    @MainActor
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(title: String(localized: "Home"), sections: [])
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

    /// The current mix — a soloed sound, Quick Mix, or a preset/Custom Mix — or
    /// the most recent preset when nothing is active. The header reads "Now
    /// Playing" while audio runs and "Recent" once it's paused.
    @MainActor
    private static func nowPlayingSection() -> CPListSection? {
      let header =
        AudioManager.shared.isGloballyPlaying
        ? String(localized: "Now Playing") : String(localized: "Recent")

      let item: CPListItem
      if let solo = AudioManager.shared.soloModeSound {
        item = PresetListTemplate.createSoloItem(solo)
      } else if AudioManager.shared.isQuickMix {
        item = quickMixItem()
      } else if let preset = PresetManager.shared.currentPreset {
        if preset.isDefault {
          // The default "All Sounds" mix is only worth showing once something is
          // actually selected in it; otherwise fall through to the empty state.
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

    /// Quick Mix row for the Now Playing section — taps jump straight to the
    /// Now Playing screen (the mix is already assembled in the Quick Mix tab).
    private static func quickMixItem() -> CPListItem {
      let titles = AudioManager.shared.sounds
        .filter { $0.isSelected }
        .map { $0.title }
      let item = CPListItem(
        text: String(localized: "Quick Mix"),
        detailText: titles.isEmpty ? nil : titles.joined(separator: ", ")
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

    /// Favorited (starred) items in the user's saved order, sharing the
    /// `GlobalSettings.starredItems` token list with the iPad sidebar. Quick Mix
    /// has its own tab, so its token is skipped.
    @MainActor
    private static func favoritesSection() -> CPListSection? {
      let presets = PresetManager.shared.presets
      let items: [CPListItem] = GlobalSettings.shared.starredItems.compactMap { token in
        if let sound = AudioManager.shared.sound(forSoloToken: token) {
          return PresetListTemplate.createSoloItem(sound)
        }
        switch token {
        case GlobalSettings.allSoundsToken:
          guard let defaultPreset = presets.first(where: { $0.isDefault }) else { return nil }
          return PresetListTemplate.createAllSoundsItem(defaultPreset)
        case GlobalSettings.quickMixToken:
          return nil
        default:
          guard let preset = presets.first(where: { $0.id.uuidString == token }) else { return nil }
          return PresetListTemplate.createPresetListItem(preset)
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
