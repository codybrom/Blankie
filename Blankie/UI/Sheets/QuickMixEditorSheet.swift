//
//  QuickMixEditorSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 2/22/26.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct QuickMixEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let globalSettings = GlobalSettings.shared
    private let audioManager = AudioManager.shared
    @State private var selectedSounds: [String] = []
    /// Stored names with no loaded sound yet (custom sounds still loading),
    /// carried through Done so the editor never prunes them.
    @State private var unresolvedSounds: [String] = []

    /// Still-loading members not since picked by name; they keep their slots.
    private var pendingSounds: [String] {
      unresolvedSounds.filter { !selectedSounds.contains($0) }
    }

    var body: some View {
      NavigationStack {
        List {
          Section {
            Text(
              "Quick Mix is a simple soundboard for quick access in CarPlay and Home Screen widgets. Unlike presets, it doesn't remember your sounds or volume levels."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }

          Section {
            NavigationLink {
              QuickMixSoundPicker(
                selectedSounds: $selectedSounds, reservedSlots: pendingSounds.count)
            } label: {
              HStack {
                Text("Choose Sounds")
                Spacer()
                Text("\(selectedSounds.count)")
                  .foregroundStyle(.secondary)
              }
            }
          }

          // Order section — drag to reorder
          Section {
            if selectedSounds.isEmpty {
              Text("No sounds selected")
                .foregroundStyle(.secondary)
            } else {
              ForEach(selectedSounds, id: \.self) { fileName in
                if let sound = audioManager.sounds.first(where: { $0.fileName == fileName }) {
                  HStack(spacing: 12) {
                    Image(systemName: sound.systemIconName)
                      .foregroundColor(.accentColor)
                      .frame(width: 20)
                      .accessibilityHidden(true)
                    Text(sound.localizedTitle)
                  }
                  .accessibilityElement(children: .combine)
                  .accessibilityLabel(Text(sound.localizedTitle))
                }
              }
              .onMove { from, to in
                selectedSounds.move(fromOffsets: from, toOffset: to)
              }
              .onDelete { indices in
                selectedSounds.remove(atOffsets: indices)
              }
            }
          } header: {
            Text("Sounds (\(selectedSounds.count + pendingSounds.count)/8)")
          } footer: {
            if !selectedSounds.isEmpty {
              Text("Drag to reorder, swipe to remove")
            }
          }
          .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Edit Quick Mix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              globalSettings.setQuickMixSoundFileNames(selectedSounds + pendingSounds)
              // Stop any sound that was just removed from an active mix.
              audioManager.reconcileQuickMixMembership()
              dismiss()
            }
            .disabled(selectedSounds.isEmpty)
            .tint(Color.primary)
          }
        }
      }
      .onAppear {
        // Drop entries that can't stand alone (preset-only), so the order list,
        // the count, and what Done saves match what's selectable. Names that
        // don't resolve yet are kept aside rather than dropped.
        let stored = globalSettings.quickMixSoundFileNames
        selectedSounds = stored.filter { fileName in
          audioManager.sounds.contains { $0.fileName == fileName && !$0.isPresetUseOnly }
        }
        unresolvedSounds = stored.filter { fileName in
          !audioManager.sounds.contains { $0.fileName == fileName }
        }
      }
      // A member that finishes loading while the editor is open joins the
      // selection in its slot, so it can be reordered or removed.
      .onChange(of: audioManager.sounds.map(\.fileName)) { _, loaded in
        let arrived = unresolvedSounds.filter(loaded.contains)
        guard !arrived.isEmpty else { return }
        unresolvedSounds.removeAll(where: arrived.contains)
        for fileName in arrived where !selectedSounds.contains(fileName) {
          let standsAlone = audioManager.sounds.contains {
            $0.fileName == fileName && !$0.isPresetUseOnly
          }
          if standsAlone { selectedSounds.append(fileName) }
        }
      }
      // Quick Mix has no preset, so use the app accent. Tinting the whole sheet
      // keeps the accent-colored sound icons stable across interactions.
      .tint(globalSettings.customAccentColor ?? .accentColor)
    }
  }

  // MARK: - Sound Picker (select/deselect only)

  struct QuickMixSoundPicker: View {
    @Binding var selectedSounds: [String]
    /// Slots held by members that are still loading.
    var reservedSlots = 0
    private let audioManager = AudioManager.shared
    private let globalSettings = GlobalSettings.shared

    private var eligibleSounds: [Sound] {
      // Preset-use-only sounds (explicit or implied by a non-looping one-shot)
      // can't stand alone, so they're never eligible for Quick Mix.
      audioManager.sounds
        .filter { !$0.isPresetUseOnly }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
      List {
        ForEach(eligibleSounds) { sound in
          let isSelected = selectedSounds.contains(sound.fileName)
          Button {
            if isSelected {
              selectedSounds.removeAll { $0 == sound.fileName }
            } else if selectedSounds.count + reservedSlots < 8 {
              selectedSounds.append(sound.fileName)
            }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 20)
                .accessibilityHidden(true)
              Text(sound.localizedTitle)
                .foregroundColor(.primary)
              Spacer()
              if isSelected {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
                  .accessibilityHidden(true)
              }
            }
          }
          .disabled(!isSelected && selectedSounds.count + reservedSlots >= 8)
          .accessibilityLabel(Text(sound.localizedTitle))
          .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
      }
      .navigationTitle("Choose Sounds")
      .navigationBarTitleDisplayMode(.inline)
      .tint(globalSettings.customAccentColor ?? .accentColor)
    }
  }

  #Preview {
    QuickMixEditorSheet()
  }
#endif
