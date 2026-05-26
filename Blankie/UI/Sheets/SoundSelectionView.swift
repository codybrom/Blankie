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
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var presetManager = PresetManager.shared

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
              macRow(for: sound)
              if sound.id != orderedSounds.last?.id {
                Divider().padding(.leading, 52)
              }
            }
          }
        }
      }
      .frame(minWidth: 380, minHeight: 440)
      .navigationTitle("Sounds")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Clear All") { handleClearAll() }
            .disabled(selectedSounds.isEmpty)
        }
      }
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

          Image(systemName: sound.systemIconName)
            .font(.body)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 22)

          Text(sound.title)
            .foregroundStyle(.primary)

          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
      }
      .buttonStyle(.plain)
    }
  #else
    private func soundRowContent(for sound: Sound) -> some View {
      HStack(spacing: 12) {
        let isRowSelected = selectedSounds.contains(sound.fileName)

        Image(systemName: sound.systemIconName)
          .foregroundColor(isRowSelected ? .accentColor : .white)
          .frame(width: 20)

        Text(sound.title)

        Spacer()

        Image(systemName: isRowSelected ? "checkmark" : "")
          .foregroundStyle(.accent)
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
    }
  #endif
}
