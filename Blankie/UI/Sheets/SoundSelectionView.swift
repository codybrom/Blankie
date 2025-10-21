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
  let editingPreset: Preset? // The preset being edited
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var presetManager = PresetManager.shared

  private func handleSoundToggle(_ sound: Sound) {
    let wasSelected = selectedSounds.contains(sound.fileName)
    let isEditingActivePreset = editingPreset?.id == presetManager.currentPreset?.id

    if wasSelected {
      // Deselecting sound
      selectedSounds.remove(sound.fileName)

      // If editing the active preset and playback is active, stop the sound immediately
      if isEditingActivePreset, audioManager.isGloballyPlaying {
        sound.isSelected = false
        print("🎵 SoundSelectionView: Immediately stopping '\(sound.title)' during preset edit")
      }
    } else {
      // Selecting sound
      selectedSounds.insert(sound.fileName)

      // If editing the active preset and playback is active, start the sound at 75%
      if isEditingActivePreset, audioManager.isGloballyPlaying {
        sound.volume = 0.75
        sound.isSelected = true
        print("🎵 SoundSelectionView: Immediately starting '\(sound.title)' at 75% during preset edit")
      }
    }
  }

  private func handleClearAll() {
    let isEditingActivePreset = editingPreset?.id == presetManager.currentPreset?.id

    // If editing the active preset and playback is active, stop all currently selected sounds
    if isEditingActivePreset, audioManager.isGloballyPlaying {
      for fileName in selectedSounds {
        if let sound = orderedSounds.first(where: { $0.fileName == fileName }) {
          sound.isSelected = false
          print("🎵 SoundSelectionView: Immediately stopping '\(sound.title)' during Clear All")
        }
      }
    }

    // Clear the selected sounds set
    selectedSounds.removeAll()
  }

  private func soundRowContent(for sound: Sound) -> some View {
    HStack(spacing: 12) {
      let isRowSelected = selectedSounds.contains(sound.fileName)

      Image(systemName: sound.systemIconName)
        .foregroundColor(isRowSelected ? sound.customColor : .white)
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
