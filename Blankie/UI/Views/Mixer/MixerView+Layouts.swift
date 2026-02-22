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
      List {
        ForEach(filteredSounds) { sound in
          soundRow(for: sound)
            .id("\(sound.id)-\(sound.isSelected)-\(audioManager.isGloballyPlaying)-\(soundsUpdateTrigger)")
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        }
        .onMove(perform: moveItems)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .id("\(globalSettings.showSoundNames)-\(soundsUpdateTrigger)")
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
      print("📱 iPadLayout: moveItems called - source: \(source), destination: \(destination)")

      // Check if we have a current preset (not default)
      if let preset = presetManager.currentPreset, !preset.isDefault {
        print("📱 iPadLayout: Moving sounds in preset '\(preset.name)'")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        print("📱 iPadLayout: Displayed sounds count: \(displayedSounds.count)")
        print("📱 iPadLayout: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          print("📱 iPadLayout: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        print("📱 iPadLayout: New order after move: \(newOrder)")

        // Build the complete sound order for the preset
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds from the preset that aren't currently displayed (e.g., hidden sounds)
        let displayedSet = Set(newOrder)
        for state in preset.soundStates where !displayedSet.contains(state.fileName) {
          completeOrder.append(state.fileName)
        }

        print("📱 iPadLayout: Complete order being sent: \(completeOrder)")

        // Update the preset with the new order
        presetManager.updateCurrentPresetWithOrder(completeOrder)

        // Force UI refresh
        soundsUpdateTrigger += 1
        print("📱 iPadLayout: UI refresh triggered")
      } else {
        // We're reordering the main sound grid (default preset or no preset)
        print("📱 iPadLayout: Moving sounds in default view")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        print("📱 iPadLayout: Displayed sounds count: \(displayedSounds.count)")
        print("📱 iPadLayout: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          print("📱 iPadLayout: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        print("📱 iPadLayout: New order after move: \(newOrder)")

        // Build the complete default order
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds that aren't currently displayed
        let displayedSet = Set(newOrder)
        for fileName in audioManager.defaultSoundOrder where !displayedSet.contains(fileName) {
          completeOrder.append(fileName)
        }

        print("📱 iPadLayout: Complete default order being saved: \(completeOrder)")

        // Update the default order
        audioManager.defaultSoundOrder = completeOrder
        UserDefaults.standard.set(completeOrder, forKey: "defaultSoundOrder")
        audioManager.objectWillChange.send()

        // Force UI refresh
        soundsUpdateTrigger += 1
        print("📱 iPadLayout: UI refresh triggered for default view")
      }
    }

    @ViewBuilder
    private func soundRow(for sound: Sound) -> some View {
      SoundRowView(sound: sound, globalSettings: globalSettings, audioManager: audioManager)
    }
  }
#endif
