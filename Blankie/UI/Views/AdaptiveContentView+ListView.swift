//
//  AdaptiveContentView+ListView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  // Separate view struct to properly observe Sound changes
  struct SoundRowView: View {
    @ObservedObject var sound: Sound
    @ObservedObject var globalSettings: GlobalSettings
    @ObservedObject var audioManager: AudioManager

    var body: some View {
      HStack(spacing: 16) {
        soundRowIcon
        soundRowControls
      }
      .background(Color.clear)
    }

    private var soundRowIcon: some View {
      ZStack {
        Circle()
          .fill(
            !audioManager.isGloballyPlaying || !sound.isSelected
              ? .clear
              : (sound.customColor ?? (globalSettings.customAccentColor ?? .accentColor))
              .opacity(0.2)
          )
          .frame(width: 50, height: 50)

        Image(systemName: sound.systemIconName)
          .font(.system(size: 24))
          .foregroundColor(
            !audioManager.isGloballyPlaying
              ? .gray
              : (sound.isSelected
                ? (sound.customColor ?? (globalSettings.customAccentColor ?? .accentColor))
                : .gray))
      }
      .onTapGesture {
        // If global playback is paused and this sound is already selected,
        // start global playback instead of deselecting the sound
        if !audioManager.isGloballyPlaying && sound.isSelected {
          audioManager.setGlobalPlaybackState(true)
        } else {
          sound.toggle()
        }
      }
    }

    private var soundRowControls: some View {
      VStack(alignment: .leading, spacing: 4) {
        if !globalSettings.showSoundNames {
          Spacer()
        }
        if globalSettings.showSoundNames {
          HStack {
            Text(LocalizedStringKey(sound.title))
              .font(
                .callout.weight(
                  Locale.current.scriptCategory == .standard ? .regular : .thin)
              )
              .foregroundColor(.primary)

            Spacer()

            Text("\(Int(sound.volume * 100))%")
              .font(.caption)
              .foregroundColor(.secondary)
              .monospacedDigit()
          }
        }

        // Volume slider
        Slider(
          value: Binding(
            get: { Double(sound.volume) },
            set: { sound.volume = Float($0) }
          ),
          in: 0 ... 1
        )
        .tint(
          sound.isSelected
            ? (sound.customColor ?? (globalSettings.customAccentColor ?? .accentColor))
            : .gray
        )
        .disabled(!sound.isSelected)

        if !globalSettings.showSoundNames {
          Spacer()
        }
      }
    }
  }

  extension AdaptiveContentView {
    // List view for small devices
    var soundListView: some View {
      return List {
        ForEach(filteredSounds) { sound in
          soundRow(for: sound)
            .id("\(sound.id)-\(sound.isSelected)-\(audioManager.isGloballyPlaying)-\(soundsUpdateTrigger)")
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .contextMenu {
              // Solo Mode - only show if not already in solo mode
              if audioManager.soloModeSound?.id != sound.id {
                Button(action: {
                  withAnimation(.easeInOut(duration: 0.3)) {
                    audioManager.toggleSoloMode(for: sound)
                  }
                }) {
                  Label("Solo", systemImage: "headphones")
                }
                .sensoryFeedback(.selection, trigger: audioManager.soloModeSound?.id)
              }

              // Customize Sound
              Button(action: {
                soundToEdit = sound
              }) {
                Label("Customize", systemImage: "paintbrush")
              }

              Divider()

              // Reorder
              Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                  if editMode == .active {
                    exitEditMode()
                  } else {
                    enterEditMode()
                  }
                }
              }) {
                Label(
                  editMode == .active ? "Done Reordering" : "Reorder",
                  systemImage: editMode == .active ? "checkmark" : "arrow.up.arrow.down"
                )
              }
            }
        }
        .onMove(perform: editMode == .active ? moveItems : nil)
        .deleteDisabled(true)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .environment(\.editMode, $editMode)
      .transition(.opacity)
      .padding(.top, 8)
      .id("\(globalSettings.showSoundNames)-\(soundsUpdateTrigger)")
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
      print("📱 ListView: moveItems called - source: \(source), destination: \(destination)")

      // Check if we have a current preset (not default)
      if let preset = presetManager.currentPreset, !preset.isDefault {
        print("📱 ListView: Moving sounds in preset '\(preset.name)'")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        print("📱 ListView: Displayed sounds count: \(displayedSounds.count)")
        print("📱 ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          print("📱 ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        print("📱 ListView: New order after move: \(newOrder)")

        // Build the complete sound order for the preset
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds from the preset that aren't currently displayed (e.g., hidden sounds)
        let displayedSet = Set(newOrder)
        for state in preset.soundStates where !displayedSet.contains(state.fileName) {
          completeOrder.append(state.fileName)
        }

        print("📱 ListView: Complete order being sent: \(completeOrder)")

        // Update the preset with the new order
        presetManager.updateCurrentPresetWithOrder(completeOrder)

        // Force UI refresh
        soundsUpdateTrigger += 1
        print("📱 ListView: UI refresh triggered")
      } else {
        // We're reordering the main sound grid (default preset or no preset)
        print("📱 ListView: Moving sounds in default view")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        print("📱 ListView: Displayed sounds count: \(displayedSounds.count)")
        print("📱 ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          print("📱 ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        print("📱 ListView: New order after move: \(newOrder)")

        // Build the complete default order
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds that aren't currently displayed
        let displayedSet = Set(newOrder)
        for fileName in audioManager.defaultSoundOrder where !displayedSet.contains(fileName) {
          completeOrder.append(fileName)
        }

        print("📱 ListView: Complete default order being saved: \(completeOrder)")

        // Update the default order
        audioManager.defaultSoundOrder = completeOrder
        UserDefaults.standard.set(completeOrder, forKey: "defaultSoundOrder")
        audioManager.objectWillChange.send()

        // Force UI refresh
        soundsUpdateTrigger += 1
        print("📱 ListView: UI refresh triggered for default view")
      }
    }

    private func getSoundAuthor(for sound: Sound) -> String? {
      // Check if it's a custom sound first
      if isCustomSound(sound) {
        return "You" // Custom sounds are created by the user
      }

      // For built-in sounds, get author from credits
      let credits = SoundCreditsManager.shared.credits
      return credits.first { $0.soundName == sound.fileName || $0.name == sound.title }?.author
    }

    private func isCustomSound(_ sound: Sound) -> Bool {
      // Custom sounds typically have higher defaultOrder values (1000+)
      // or are not found in the built-in credits
      let credits = SoundCreditsManager.shared.credits
      let isInCredits = credits.contains {
        $0.soundName == sound.fileName || $0.name == sound.title
      }
      return !isInCredits
    }

    @ViewBuilder
    private func soundRow(for sound: Sound) -> some View {
      SoundRowView(sound: sound, globalSettings: globalSettings, audioManager: audioManager)
    }
  }
#endif
