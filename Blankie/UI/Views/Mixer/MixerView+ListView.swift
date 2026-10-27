//
//  MixerView+ListView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/25.
//

import SwiftUI
import os

#if os(iOS) || os(visionOS)
  // Separate struct so each row observes its own Sound.
  struct SoundRowView: View {
    let sound: Sound
    var globalSettings: GlobalSettings
    let audioManager: AudioManager
    let presetManager = PresetManager.shared
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
        audioManager.toggleOrResume(sound)
      }
      .glassEffect(.regular, in: .rect(cornerRadius: 12))
      // Keyed to the sound's own selection (as in GridSoundButton) so global play/pause stays quiet.
      .sensoryFeedback(.selection, trigger: sound.isSelected)
    }

    private var accentColor: Color {
      if let preset = presetManager.currentPreset, !preset.isDefault,
        let presetColor = preset.accentColor
      {
        return presetColor
      }
      return globalSettings.customAccentColor ?? .accentColor
    }

    private var soundRowIcon: some View {
      ZStack {
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
      // VoiceOver toggle; the volume slider stays a separate adjustable element.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(sound.localizedTitle))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(sound.isSelected ? [.isSelected] : [])
      .accessibilityAction {
        audioManager.toggleOrResume(sound)
      }
    }

    private var soundRowControls: some View {
      VStack(alignment: .leading, spacing: 4) {
        if !globalSettings.showSoundNames {
          Spacer()
        }
        if globalSettings.showSoundNames {
          HStack {
            Text(sound.localizedTitle)
              .font(
                .callout.weight(
                  Locale.current.scriptCategory == .standard ? .regular : .thin)
              )
              .foregroundColor(.primary)
              // The icon's accessibility label already reads the title.
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
              // The slider already announces this as its value.
              .accessibilityHidden(true)
          }
        }

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
        .accessibilityLabel(Text(sound.localizedTitle))
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
      // The floating mini player's safe-area inset doesn't reach this nested List.
      .contentMargins(.bottom, 72, for: .scrollContent)
      .transition(.opacity)
      .id("\(globalSettings.showSoundNames)")
    }

    // Reorder handler shared by the list and grid views in `mainContentView`.
    func moveItems(from source: IndexSet, to destination: Int) {
      Logger.ui.debug("ListView: moveItems called - source: \(source), destination: \(destination)")

      if let preset = presetManager.currentPreset, !preset.isDefault {
        Logger.ui.debug("ListView: Moving sounds in preset '\(preset.name)'")

        let displayedSounds = filteredSounds
        Logger.ui.debug("ListView: Displayed sounds count: \(displayedSounds.count)")
        Logger.ui.debug("ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        var newOrder = displayedSounds.map { $0.fileName }

        for index in source where index < newOrder.count {
          Logger.ui.debug(
            "ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        newOrder.move(fromOffsets: source, toOffset: destination)
        Logger.ui.debug("ListView: New order after move: \(newOrder)")

        var completeOrder = newOrder

        // Append the preset's hidden sounds so they keep a place in the order.
        let displayedSet = Set(newOrder)
        for state in preset.soundStates where !displayedSet.contains(state.fileName) {
          completeOrder.append(state.fileName)
        }

        Logger.ui.debug("ListView: Complete order being sent: \(completeOrder)")

        presetManager.updateCurrentPresetWithOrder(completeOrder)
      } else {
        Logger.ui.debug("ListView: Moving sounds in default view")

        let displayedSounds = filteredSounds
        Logger.ui.debug("ListView: Displayed sounds count: \(displayedSounds.count)")
        Logger.ui.debug("ListView: Displayed sounds order: \(displayedSounds.map { $0.fileName })")

        var newOrder = displayedSounds.map { $0.fileName }

        for index in source where index < newOrder.count {
          Logger.ui.debug(
            "ListView: Moving '\(newOrder[index])' from index \(index) to \(destination)")
        }

        newOrder.move(fromOffsets: source, toOffset: destination)
        Logger.ui.debug("ListView: New order after move: \(newOrder)")

        var completeOrder = newOrder

        let displayedSet = Set(newOrder)
        for fileName in audioManager.defaultSoundOrder where !displayedSet.contains(fileName) {
          completeOrder.append(fileName)
        }

        Logger.ui.debug("ListView: Complete default order being saved: \(completeOrder)")

        audioManager.defaultSoundOrder = completeOrder
        // Launch reads the order back from the app group suite.
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
