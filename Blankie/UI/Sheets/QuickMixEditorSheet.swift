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

    var body: some View {
      NavigationStack {
        List {
          Section {
            Text(
              "Quick Mix is a simple soundboard for quick access in CarPlay and beyond. Unlike presets, it doesn't have customizable volume, doesn't remember your sounds, and can't use custom sounds."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }

          Section {
            NavigationLink {
              QuickMixSoundPicker(selectedSounds: $selectedSounds)
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
                    Text(LocalizedStringKey(sound.title))
                  }
                  .accessibilityElement(children: .combine)
                  .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
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
            Text("Sounds (\(selectedSounds.count)/8)")
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
              globalSettings.setQuickMixSoundFileNames(selectedSounds)
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
        // Drop any stale entries that can no longer stand alone (preset-only or
        // since-removed sounds), so the order list, the count, and what Done
        // saves all stay consistent with what's actually selectable.
        selectedSounds = globalSettings.quickMixSoundFileNames.filter { fileName in
          audioManager.sounds.contains { $0.fileName == fileName && !$0.isPresetUseOnly }
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
    private let audioManager = AudioManager.shared
    private let globalSettings = GlobalSettings.shared

    private var builtInSounds: [Sound] {
      // Preset-use-only sounds (explicit or implied by a non-looping one-shot)
      // can't stand alone, so they're never eligible for Quick Mix.
      audioManager.sounds
        .filter { !$0.isCustom && !$0.isPresetUseOnly }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
      List {
        ForEach(builtInSounds) { sound in
          let isSelected = selectedSounds.contains(sound.fileName)
          Button {
            if isSelected {
              selectedSounds.removeAll { $0 == sound.fileName }
            } else if selectedSounds.count < 8 {
              selectedSounds.append(sound.fileName)
            }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 20)
                .accessibilityHidden(true)
              Text(LocalizedStringKey(sound.title))
                .foregroundColor(.primary)
              Spacer()
              if isSelected {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
                  .accessibilityHidden(true)
              }
            }
          }
          .disabled(!isSelected && selectedSounds.count >= 8)
          .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
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
