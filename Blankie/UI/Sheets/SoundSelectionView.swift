//
//  SoundSelectionView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct SoundSelectionView: View {
  @Binding var selectedSounds: Set<String>
  let orderedSounds: [Sound]
  let editingPreset: Preset?
  @Environment(\.dismiss) private var dismiss
  private let audioManager = AudioManager.shared
  private let presetManager = PresetManager.shared

  private func handleSoundToggle(_ sound: Sound) {
    let isEditingActivePreset = editingPreset?.id == presetManager.currentPreset?.id

    if selectedSounds.contains(sound.fileName) {
      selectedSounds.remove(sound.fileName)

      // Stop the sound immediately when removing from the active preset
      if isEditingActivePreset, audioManager.isGloballyPlaying {
        sound.isSelected = false
      }
    } else {
      selectedSounds.insert(sound.fileName)
    }
  }

  private func handleClearAll() {
    let isEditingActivePreset = editingPreset?.id == presetManager.currentPreset?.id

    if isEditingActivePreset, audioManager.isGloballyPlaying {
      for fileName in selectedSounds {
        if let sound = orderedSounds.first(where: { $0.fileName == fileName }) {
          sound.isSelected = false
        }
      }
    }

    selectedSounds.removeAll()
  }

  #if os(macOS)
    var body: some View {
      VStack(spacing: 0) {
        // Hint header: make it obvious this is a tap-to-toggle multi-select.
        HStack {
          Text("Tap a sound to add or remove it from this preset")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(selectedSounds.count) selected")
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()

        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(orderedSounds, id: \.id) { sound in
              // Wrap row + inter-row divider so each ForEach element yields one
              // view (constant child count), instead of a bare trailing if.
              VStack(spacing: 0) {
                macRow(for: sound)
                if sound.id != orderedSounds.last?.id {
                  Divider().padding(.leading, 52)
                }
              }
            }
          }
        }
      }
      .frame(minWidth: 380, minHeight: 440)
      .navigationTitle("Sounds")
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button("Clear All") { handleClearAll() }
            .disabled(selectedSounds.isEmpty)
            .tint(Color.primary)
        }
      }
      // Rows style their selection via the environment tint (.tint / .accent), so
      // anchor it to the app accent for a stable, consistent selection color.
      .tint(GlobalSettings.shared.customAccentColor ?? .accentColor)
    }

    private func macRow(for sound: Sound) -> some View {
      let isSelected = selectedSounds.contains(sound.fileName)
      return Button {
        handleSoundToggle(sound)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .frame(width: 24)
            .accessibilityHidden(true)

          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(sound.localizedTitle)
                .foregroundStyle(.primary)
              if let subtitle = sound.localizedSubtitle {
                Text(subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          } icon: {
            Image(systemName: sound.systemIconName)
              .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          }

          Spacer()

          SoundCreditInfoButton(sound: sound, accent: editingPreset?.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(sound.localizedTitle))
      .accessibilityAddTraits(isSelected ? [.isSelected] : [])
      .accessibilityHint("Adds or removes this sound from the preset")
    }
  #else
    private func soundRowContent(for sound: Sound) -> some View {
      HStack(spacing: 12) {
        let isRowSelected = selectedSounds.contains(sound.fileName)

        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(sound.localizedTitle)
            if let subtitle = sound.localizedSubtitle {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        } icon: {
          Image(systemName: sound.systemIconName)
            .foregroundStyle(isRowSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
        }

        Spacer()

        SoundCreditInfoButton(sound: sound, accent: editingPreset?.accentColor)

        Image(systemName: "checkmark")
          .foregroundStyle(.tint)
          .opacity(isRowSelected ? 1 : 0)
          .accessibilityHidden(true)
      }
    }

    var body: some View {
      List {
        ForEach(orderedSounds, id: \.id) { sound in
          soundRowContent(for: sound)
            .contentShape(Rectangle())
            .onTapGesture {
              handleSoundToggle(sound)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(sound.localizedTitle))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selectedSounds.contains(sound.fileName) ? [.isSelected] : [])
            .accessibilityHint("Adds or removes this sound from the preset")
        }
      }
      .listStyle(.plain)
      .navigationTitle("Sounds")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarItems(
        trailing: Button("Clear All") {
          handleClearAll()
        }
        .disabled(selectedSounds.isEmpty)
      )
      .tint(GlobalSettings.shared.customAccentColor ?? .accentColor)
    }
  #endif
}
