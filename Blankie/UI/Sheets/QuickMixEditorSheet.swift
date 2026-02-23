//
//  QuickMixEditorSheet.swift
//  Blankie
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct QuickMixEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var globalSettings = GlobalSettings.shared
    @ObservedObject private var audioManager = AudioManager.shared
    @State private var selectedSounds: [String] = []

    private var orderedSounds: [Sound] {
      selectedSounds.compactMap { fileName in
        audioManager.sounds.first { $0.fileName == fileName }
      }
    }

    var body: some View {
      NavigationStack {
        List {
          Section {
            Text("Quick Mix is a simple soundboard for quick access in CarPlay and other places coming soon. Unlike presets, it doesn't save which sounds are active, remember volume levels, or restore on next launch. Quick Mix cannot use custom sounds.")
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
                      .foregroundColor(sound.customColor ?? .accentColor)
                      .frame(width: 20)
                    Text(sound.title)
                  }
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
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              globalSettings.setQuickMixSoundFileNames(selectedSounds)
              dismiss()
            }
            .disabled(selectedSounds.isEmpty)
          }
        }
      }
      .onAppear {
        selectedSounds = globalSettings.quickMixSoundFileNames
      }
    }
  }

  // MARK: - Sound Picker (select/deselect only)

  struct QuickMixSoundPicker: View {
    @Binding var selectedSounds: [String]
    @ObservedObject private var audioManager = AudioManager.shared

    private var builtInSounds: [Sound] {
      audioManager.sounds.filter { !$0.isCustom }.sorted { $0.title < $1.title }
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
                .foregroundColor(isSelected ? sound.customColor ?? .accentColor : .secondary)
                .frame(width: 20)
              Text(sound.title)
                .foregroundColor(.primary)
              Spacer()
              if isSelected {
                Image(systemName: "checkmark")
                  .foregroundStyle(.accent)
              }
            }
          }
          .disabled(!isSelected && selectedSounds.count >= 8)
        }
      }
      .navigationTitle("Choose Sounds")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  #Preview {
    QuickMixEditorSheet()
  }
#endif
