//
//  EditPresetSections.swift
//  Blankie
//
//  Created by Cody Bromley on 6/11/25.
//

import PhotosUI
import SwiftUI

// MARK: - Default Preset Section

// MARK: - Core Section (Name and Sounds)

extension EditPresetSheet {
  var coreSection: some View {
    Section {
      // Name field
      LabeledContent("Name") {
        TextField("Required", text: $presetName)
          .multilineTextAlignment(.trailing)
          .onChange(of: presetName) { _, _ in
            applyChangesInstantly()
          }
      }

      // Sounds field
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          LabeledContent("Sounds") {
            HStack {
              Text("\(selectedSounds.count) Selected")
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
          }
        }
        .buttonStyle(.plain)
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          LabeledContent("Sounds") {
            Text("\(selectedSounds.count) Selected")
              .foregroundStyle(.secondary)
          }
        }
      #endif
    }
    .onChange(of: selectedSounds) { _, newValue in
      // Update soundOrder to include new sounds and remove deselected sounds
      let validOrder = soundOrder.filter { newValue.contains($0) }
      let newSounds = newValue.filter { !validOrder.contains($0) }
      soundOrder = validOrder + newSounds.sorted()

      applyChangesInstantly()
    }
  }
}

// MARK: - Now Playing Section (Creator & Artwork)

extension EditPresetSheet {
  var nowPlayingSection: some View {
    Section("Now Playing") {
      // Creator field (only for non-default presets)
      if !preset.isDefault {
        LabeledContent("Creator") {
          TextField("Optional", text: $creatorName)
            .multilineTextAlignment(.trailing)
            .onChange(of: creatorName) { _, _ in
              applyChangesInstantly()
            }
        }
      }

      // Artwork field
      LabeledContent("Artwork") {
        HStack(spacing: 8) {
          if artworkData != nil {
            Button {
              artworkData = nil
              artworkId = nil
              // Apply changes to persist the removal
              applyChangesInstantly()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
          }

          Button {
            showingImagePicker = true
          } label: {
            artworkPreview
          }
          .buttonStyle(.plain)
        }
      }

      AnimatedArtworkPicker(
        artwork: $animatedArtwork,
        staticArtworkPath: $staticArtworkPath,
        onChange: applyChangesInstantly
      )
    }
    .onChange(of: artworkData) { _, _ in
      applyChangesInstantly()
    }
  }
}

// MARK: - Error Section

extension EditPresetSheet {
  @ViewBuilder
  var errorSection: some View {
    if let error = error {
      Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
  }
}

// MARK: - Basic Info Section (deprecated - use nowPlayingSection)

extension EditPresetSheet {
  var basicInfoSection: some View {
    nowPlayingSection
  }
}

// MARK: - Creator Section (deprecated - now part of nowPlayingInfoSection)

extension EditPresetSheet {
  var creatorSection: some View {
    EmptyView()
  }
}

// MARK: - Artwork Section (deprecated - now part of nowPlayingInfoSection)

extension EditPresetSheet {
  var artworkSection: some View {
    EmptyView()
  }
}

// MARK: - Artwork Preview

extension EditPresetSheet {
  @ViewBuilder
  var artworkPreview: some View {
    if let artworkData = artworkData {
      #if os(iOS) || os(visionOS)
        if let uiImage = UIImage(data: artworkData) {
          Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      #elseif os(macOS)
        if let nsImage = NSImage(data: artworkData) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      #endif
    } else {
      Text("Select Image")
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Sounds Section

extension EditPresetSheet {
  var soundsSection: some View {
    Section {
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          LabeledContent("Sounds") {
            HStack {
              Text("\(selectedSounds.count) Selected")
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
          }
        }
        .buttonStyle(.plain)
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          LabeledContent("Sounds") {
            Text("\(selectedSounds.count) Selected")
              .foregroundStyle(.secondary)
          }
        }
      #endif
    }
    .onChange(of: selectedSounds) { _, _ in
      applyChangesInstantly()
    }
  }
}

// MARK: - Sound Order Section (Reorderable)

extension EditPresetSheet {
  var soundOrderSection: some View {
    #if os(iOS) || os(visionOS)
      Section {
        if selectedSounds.isEmpty {
          Text("No sounds selected")
            .foregroundStyle(.secondary)
            .font(.subheadline)
        } else {
          ForEach(orderedSelectedSounds) { sound in
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

              Text(sound.title)
                .font(.body)

              Spacer()
            }
            .padding(.vertical, 4)
          }
          .onMove { from, to in
            moveSound(from: from, to: to)
          }
        }
      } header: {
        HStack {
          Text("Sound Order")

          Spacer()

          if !selectedSounds.isEmpty {
            Button {
              withAnimation {
                soundEditMode = soundEditMode == .active ? .inactive : .active
              }
            } label: {
              Text(soundEditMode == .active ? "Done" : "Edit")
                .font(.body)
            }
          }
        }
      } footer: {
        if !selectedSounds.isEmpty {
          Text("Drag sounds to reorder how they appear in the preset")
            .font(.caption)
        }
      }
      .environment(\.editMode, $soundEditMode)
    #else
      Section {
        if selectedSounds.isEmpty {
          Text("No sounds selected")
            .foregroundStyle(.secondary)
            .font(.subheadline)
        } else {
          ForEach(orderedSelectedSounds) { sound in
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

              Text(sound.title)
                .font(.body)

              Spacer()

              // macOS: Show move up/down buttons instead of drag-and-drop
              HStack(spacing: 4) {
                Button {
                  if let index = orderedSelectedSounds.firstIndex(where: { $0.id == sound.id }),
                     index > 0
                  {
                    moveSound(from: IndexSet(integer: index), to: index - 1)
                  }
                } label: {
                  Image(systemName: "chevron.up")
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(orderedSelectedSounds.first?.id == sound.id)

                Button {
                  if let index = orderedSelectedSounds.firstIndex(where: { $0.id == sound.id }),
                     index < orderedSelectedSounds.count - 1
                  {
                    moveSound(from: IndexSet(integer: index), to: index + 2)
                  }
                } label: {
                  Image(systemName: "chevron.down")
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(orderedSelectedSounds.last?.id == sound.id)
              }
            }
            .padding(.vertical, 4)
          }
        }
      } header: {
        Text("Sound Order")
      } footer: {
        if !selectedSounds.isEmpty {
          Text("Use the up/down buttons to reorder sounds")
            .font(.caption)
        }
      }
    #endif
  }

  var orderedSelectedSounds: [Sound] {
    // Filter to only include currently selected sounds
    let validOrder = soundOrder.filter { selectedSounds.contains($0) }

    // Add any newly selected sounds that aren't in the order yet
    let newSounds = selectedSounds.filter { !validOrder.contains($0) }
    let finalOrder = validOrder + newSounds.sorted()

    // Map to Sound objects
    return finalOrder.compactMap { fileName in
      audioManager.sounds.first(where: { $0.fileName == fileName })
    }
  }

  func moveSound(from source: IndexSet, to destination: Int) {
    var currentOrder = orderedSelectedSounds.map { $0.fileName }
    currentOrder.move(fromOffsets: source, toOffset: destination)

    // Update the soundOrder state
    soundOrder = currentOrder

    // Trigger UI update to save changes
    applyChangesInstantly()
  }
}

// MARK: - Delete Section

extension EditPresetSheet {
  @ViewBuilder
  var deleteSection: some View {
    Section {
      Button(role: .destructive) {
        presetToDelete = preset
      } label: {
        HStack {
          Spacer()
          Text("Delete Preset")
          Spacer()
        }
      }
    }
  }
}
