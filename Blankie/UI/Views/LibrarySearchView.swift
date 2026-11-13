//
//  LibrarySearchView.swift
//  Blankie
//
//  Created by Cody Bromley on 11/10/26.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  /// The iPhone Library's search tab: every mix, Kaleidoscope and sound by name.
  struct LibrarySearchView: View {
    /// Lets the owner push the player after a selection.
    var onSelection: (() -> Void)?

    @State private var query = ""
    private let presetManager = PresetManager.shared
    private let audioManager = AudioManager.shared
    private let globalSettings = GlobalSettings.shared

    private func matches(_ title: String) -> Bool {
      LibraryView.nameMatches(title, query: query)
    }

    private var presets: [Preset] {
      presetManager.presets.filter { matches($0.displayName) }
    }

    private var kaleidoscopes: [Sound] {
      audioManager.sounds
        .filter { $0 is KaleidoscopeSound && !$0.isPresetUseOnly && matches($0.localizedTitle) }
        .sortedByLocalizedTitle()
    }

    private var sounds: [Sound] {
      audioManager.sounds
        .filter { !($0 is KaleidoscopeSound) && !$0.isPresetUseOnly && matches($0.localizedTitle) }
        .sortedByLocalizedTitle()
    }

    var body: some View {
      let isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty
      List {
        if isSearching {
          if !presets.isEmpty {
            Section {
              ForEach(presets, id: \.id) { preset in
                PresetPickerRow(
                  preset: preset, isEditMode: false, dismissOnSelect: false, presentation: .page,
                  onSelection: onSelection)
              }
            } header: {
              Text("Presets")
            }
          }
          if !kaleidoscopes.isEmpty {
            Section {
              ForEach(kaleidoscopes, id: \.id) { sound in
                SingleSoundPickerRow(
                  sound: sound, isEditMode: false, dismissOnSelect: false, presentation: .page,
                  onSelection: onSelection)
              }
            } header: {
              Text("Kaleidoscopes")
            }
          }
          if !sounds.isEmpty {
            Section {
              ForEach(sounds, id: \.id) { sound in
                SingleSoundPickerRow(
                  sound: sound, isEditMode: false, dismissOnSelect: false, presentation: .page,
                  onSelection: onSelection)
              }
            } header: {
              Text("Sounds")
            }
          }
        }
      }
      .overlay {
        if !isSearching {
          ContentUnavailableView(
            "Search Blankie", systemImage: "magnifyingglass",
            description: Text("Find a preset, a Kaleidoscope or a sound by name."))
        } else if presets.isEmpty && kaleidoscopes.isEmpty && sounds.isEmpty {
          ContentUnavailableView.search(text: query)
        }
      }
      .searchable(text: $query, prompt: Text("Presets, Kaleidoscopes and Sounds"))
      .navigationTitle("Search")
      .navigationBarTitleDisplayMode(.inline)
      .tint(globalSettings.customAccentColor ?? .accentColor)
    }
  }
#endif
