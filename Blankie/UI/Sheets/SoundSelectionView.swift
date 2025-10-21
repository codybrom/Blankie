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
  @Environment(\.dismiss) private var dismiss

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
            if selectedSounds.contains(sound.fileName) {
              selectedSounds.remove(sound.fileName)
            } else {
              selectedSounds.insert(sound.fileName)
            }
          }
      }
    }
    .listStyle(.plain)
    .navigationTitle("Sounds")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarItems(
        trailing: Button("Clear All") {
          selectedSounds.removeAll()
        }
        .disabled(selectedSounds.isEmpty)
      )
    #else
      .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Clear All") {
              selectedSounds.removeAll()
            }
            .disabled(selectedSounds.isEmpty)
          }
        }
    #endif
  }
}
