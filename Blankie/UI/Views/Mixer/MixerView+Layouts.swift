//
//  MixerView+Layouts.swift
//  Blankie
//
//  Created by Cody Bromley on 6/2/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension MixerView {
    // MARK: - Solo Mode View

    @ViewBuilder
    func soloModeView(for soloSound: Sound) -> some View {
      VStack {
        Spacer()
        DraggableSoundIcon(
          sound: soloSound,
          maxWidth: 280,
          index: 0,
          draggedIndex: .constant(nil),
          hoveredIndex: .constant(nil),
          onDragStart: {},
          onDrop: { _ in },
          onEditSound: { sound in
            soundToEdit = sound
          },
          isSoloMode: true
        )
        .scaleEffect(1.0)
        .transition(
          .asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .scale.combined(with: .opacity)
          )
        )
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding()
    }

    // MARK: - List View

    @ViewBuilder
    var listView: some View {
      soundListView
    }

    // MARK: - Grid (tile) View

    @ViewBuilder
    var gridView: some View {
      SoundGridView(sounds: filteredSounds, onMove: moveItems)
    }

    /// Resolved view mode for the current context: per-preset override wins
    /// over the app-wide default. Solo mode and Quick Mix have their own
    /// rendering paths and don't route through here.
    var effectiveUseListView: Bool {
      if let override = presetManager.currentPreset?.viewMode {
        return override == .list
      }
      return showingListView
    }

    /// Chooses list or grid view based on per-preset override then app
    /// setting. Grid is the tile layout (matches Quick Mix visually).
    @ViewBuilder
    var soundsView: some View {
      if effectiveUseListView {
        listView
      } else {
        gridView
      }
    }

    @ViewBuilder
    private func soundRow(for sound: Sound) -> some View {
      SoundRowView(sound: sound, globalSettings: globalSettings, audioManager: audioManager)
    }
  }
#endif
