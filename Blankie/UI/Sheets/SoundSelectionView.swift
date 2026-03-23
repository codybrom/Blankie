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
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarItems(
        trailing: Button("Clear All") {
          handleClearAll()
        }
        .disabled(selectedSounds.isEmpty)
      )
    #else
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Clear All") {
            handleClearAll()
          }
          .disabled(selectedSounds.isEmpty)
        }
      }
    #endif
  }
}
