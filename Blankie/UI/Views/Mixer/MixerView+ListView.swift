//
//  MixerView+ListView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/25.
//

import SwiftUI
import os

#if os(iOS) || os(visionOS)
  // Separate view struct to properly observe Sound changes
  struct SoundRowView: View {
    let sound: Sound
    var globalSettings: GlobalSettings
    let audioManager: AudioManager
    @ObservedObject var presetManager = PresetManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      HStack(spacing: 16) {
        soundRowIcon
        soundRowControls
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(.rect(cornerRadius: 12))
      .onTapGesture {
        if !audioManager.isGloballyPlaying && sound.isSelected {
          audioManager.setGlobalPlaybackState(true)
        } else {
          sound.toggle()
        }
      }
      .glassEffect(.regular, in: .rect(cornerRadius: 12))
      // Match the grid: fire on the user's own selection toggle, not on global
      // play state, so feedback fires when toggling while paused and never
      // batch-fires on global play/pause. See GridSoundButton.
      .sensoryFeedback(.selection, trigger: sound.isSelected)
    }

    private var accentColor: Color {
      // If we are in a custom preset that has a specific color, use it to override sound colors
      if let preset = presetManager.currentPreset, !preset.isDefault,
        let presetColor = preset.accentColor
      {
        return presetColor
      }
      // Otherwise (Default preset, or custom preset with no color), respect sound's custom color
      return globalSettings.customAccentColor ?? .accentColor
    }

    private var soundRowIcon: some View {
      ZStack {
        // Progress border if enabled
        if globalSettings.showProgressBorder && audioManager.isGloballyPlaying && sound.isSelected {
          ProgressBorderView(
            iconSize: 50,
            borderWidth: 3,
            sound: sound,
            color: accentColor
          )
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }

        Image(systemName: sound.systemIconName)
          .font(.system(size: 24))
          .foregroundColor(
            !audioManager.isGloballyPlaying
              ? .gray
              : (sound.isSelected ? accentColor : .gray)
          )
      }
      .frame(width: 50, height: 50)
      .glassEffect(
        sound.isSelected && audioManager.isGloballyPlaying
          ? .regular.tint(accentColor.opacity(0.5)).interactive()
          : .regular.interactive(),
        in: .circle
      )
      .opacity(sound.isSelected ? 1.0 : 0.4)
      // VoiceOver focuses this to toggle the sound in/out of the mix and the volume slider below stays a separate adjustable element.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(sound.isSelected ? [.isSelected] : [])
      .accessibilityAction {
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
              // The row already exposes the title as its accessibility label so we hide the visible copy to prevent VoiceOver reading it twice
              .accessibilityHidden(true)

            if sound.isMusic {
              MusicTagBadge(
                isActive: sound.isSelected && audioManager.isGloballyPlaying,
                accentColor: accentColor)
            }

            Spacer()

            Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0))))
              .font(.caption)
              .foregroundColor(.secondary)
              .monospacedDigit()
              // The slider already announces this percentage as its value so  we hide the visible text to prevent VoiceOver from reading it twice
              .accessibilityHidden(true)
          }
        }

        // Volume slider
        Slider(
          value: Binding(
            get: { Double(sound.volume) },
            set: { sound.volume = Float($0) }
          ),
          in: 0...1
        )
        .tint(
          sound.isSelected ? accentColor : .gray
        )
        .disabled(!sound.isSelected)
        .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
        .accessibilityValue(
          Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0))))
        )

        if !globalSettings.showSoundNames {
          Spacer()
        }
      }
    }
  }

  extension MixerView {
    // List view for small devices
    var soundListView: some View {
      List {
        ForEach(filteredSounds) { sound in
          soundRow(for: sound)
            .id("\(sound.id)-\(sound.isSelected)-\(audioManager.isGloballyPlaying)")
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .onMove(perform: moveItems)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      // The Now Playing mini player floats over the bottom edge and its
      // safe-area-bar inset doesn't reach this nested List
      .contentMargins(.bottom, 72, for: .scrollContent)
      .transition(.opacity)
      .id("\(globalSettings.showSoundNames)")
    }

    // Reorder handler shared by the list and grid views in `mainContentView`.
    func moveItems(from source: IndexSet, to destination: Int) {
      Logger.ui.debug("ListView: moveItems called - source: \(source), destination: \(destination)")

      // Check if we have a current preset (not default)
      if let preset = presetManager.currentPreset, !preset.isDefault {
        Logger.ui.debug("ListView: Moving sounds in preset '\(preset.name)'")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        Logger.ui.debug("ListView: Displayed sounds count: \(displayedSounds.count)")
        Logger.ui.debug("ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          Logger.ui.debug(
            "ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        Logger.ui.debug("ListView: New order after move: \(newOrder)")

        // Build the complete sound order for the preset
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds from the preset that aren't currently displayed (e.g., hidden sounds)
        let displayedSet = Set(newOrder)
        for state in preset.soundStates where !displayedSet.contains(state.fileName) {
          completeOrder.append(state.fileName)
        }

        Logger.ui.debug("ListView: Complete order being sent: \(completeOrder)")

        // Update the preset with the new order. The grid re-sorts from the
        // persisted order automatically (@Observable preset/sounds reads).
        presetManager.updateCurrentPresetWithOrder(completeOrder)
      } else {
        // We're reordering the main sound grid (default preset or no preset)
        Logger.ui.debug("ListView: Moving sounds in default view")

        // Get the actual filtered sounds array that the list is displaying
        let displayedSounds = filteredSounds
        Logger.ui.debug("ListView: Displayed sounds count: \(displayedSounds.count)")
        Logger.ui.debug("ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        // Create a mutable copy of the current order
        var newOrder = displayedSounds.map { $0.fileName }

        // Debug: Show what's being moved
        for index in source where index < newOrder.count {
          Logger.ui.debug(
            "ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        // Apply the move operation
        newOrder.move(fromOffsets: source, toOffset: destination)
        Logger.ui.debug("ListView: New order after move: \(newOrder)")

        // Build the complete default order
        // Start with the new order of displayed sounds
        var completeOrder = newOrder

        // Add any sounds that aren't currently displayed
        let displayedSet = Set(newOrder)
        for fileName in audioManager.defaultSoundOrder where !displayedSet.contains(fileName) {
          completeOrder.append(fileName)
        }

        Logger.ui.debug("ListView: Complete default order being saved: \(completeOrder)")

        // Update the default order. Assigning the @Observable array re-sorts
        // the grid automatically; no manual refresh needed.
        audioManager.defaultSoundOrder = completeOrder
        // Must match the suite the order is read back from at launch
        // (UserDefaults.shared / app group); .standard silently reverts.
        UserDefaults.shared.set(completeOrder, forKey: "defaultSoundOrder")
      }
    }

    @ViewBuilder
    private func soundRow(for sound: Sound) -> some View {
      SoundRowView(sound: sound, globalSettings: globalSettings, audioManager: audioManager)
    }
  }

  #if DEBUG
    struct SoundRowView_Previews: PreviewProvider {
      static var previews: some View {
        let sound = Sound(
          title: "Rain",
          systemIconName: "cloud.rain",
          fileName: "rain",
          fileExtension: "m4a",
          defaultOrder: 1,
          lufs: nil,
          normalizationFactor: nil,
          truePeakdBTP: nil,
          needsLimiter: false,
          isCustom: false,
          fileURL: nil,
          dateAdded: nil,
          customSoundDataID: nil
        )
        sound.isSelected = true
        sound.volume = 0.75

        return VStack(spacing: 16) {
          SoundRowView(
            sound: sound,
            globalSettings: GlobalSettings.shared,
            audioManager: AudioManager.shared
          )
          .padding(.horizontal)

          SoundRowView(
            sound: Sound(
              title: "Thunder",
              systemIconName: "cloud.bolt",
              fileName: "thunder",
              fileExtension: "m4a",
              defaultOrder: 2,
              lufs: nil,
              normalizationFactor: nil,
              truePeakdBTP: nil,
              needsLimiter: false,
              isCustom: false,
              fileURL: nil,
              dateAdded: nil,
              customSoundDataID: nil
            ),
            globalSettings: GlobalSettings.shared,
            audioManager: AudioManager.shared
          )
          .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
      }
    }
  #endif
#endif
