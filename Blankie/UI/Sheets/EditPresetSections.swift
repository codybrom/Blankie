//
//  EditPresetSections.swift
//  Blankie
//
//  Created by Cody Bromley on 6/11/25.
//

import PhotosUI
import SwiftUI

// MARK: - Default Preset Section

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

// MARK: - Basic Details Section (Name, Creator)

extension EditPresetSheet {
  var basicDetailsSection: some View {
    Section {
      // Name field
      LabeledContent("Name") {
        TextField("Required", text: $presetName)
          .multilineTextAlignment(.trailing)
          .onChange(of: presetName) { _, _ in
            applyChangesInstantly()
          }
      }

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

    }
  }

  var activeAccentColor: Color {
    if useCustomTheme {
      return accentColor ?? globalSettings.customAccentColor ?? .accentColor
    } else {
      return globalSettings.customAccentColor ?? .accentColor
    }
  }
}

// MARK: - Visuals Section (Accent Color, Artwork, Lockscreen)

extension EditPresetSheet {
  var visualsSection: some View {
    Section("Appearance") {
      // Accent Color
      Toggle("Accent Color", isOn: $useCustomTheme)

      if useCustomTheme {
        SpectrumColorPicker(selectedColor: $accentColor)
          .padding(.vertical, 4)
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
        onChange: { applyChangesInstantly() }
      )
    }
    .onChange(of: artworkData) { _, _ in
      applyChangesInstantly()
    }
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

// MARK: - Sounds Section (Reorderable)

extension EditPresetSheet {
  var soundsSection: some View {
    Section {
      // Add/Edit Sounds Button
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          HStack {
            Text("Manage Sounds")
            Spacer()
            Text("\(selectedSounds.count)")
              .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
              .foregroundStyle(.tertiary)
              .imageScale(.small)
          }
        }
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          HStack {
            Text("Manage Sounds")
            Spacer()
            Text("\(selectedSounds.count)")
              .foregroundStyle(.secondary)
          }
        }
      #endif

      if selectedSounds.isEmpty {
        Text("No sounds selected")
          .foregroundStyle(.secondary)
          .font(.subheadline)
      } else {
        ForEach(orderedSelectedSounds) { sound in
          #if os(iOS)
            Button {
              navPath.append(sound)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: sound.systemIconName)
                  .font(.title3)
                  .foregroundColor(activeAccentColor)
                  .frame(width: 24)

                Text(sound.title)
                  .font(.body)

                Spacer()
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          #else
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .font(.title3)
                .foregroundColor(activeAccentColor)
                .frame(width: 24)

              Text(sound.title)
                .font(.body)

              Spacer()
            }
            .padding(.vertical, 4)
          #endif
        }
        .onMove { from, to in
          moveSound(from: from, to: to)
        }
      }
    } header: {
      Text("Sounds")
    } footer: {
      if !selectedSounds.isEmpty {
        Text("Drag sounds to reorder how they appear in the preset")
          .font(.caption)
      }
    }
    .environment(\.editMode, .constant(.active))
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
    applyChangesInstantly(skipRefresh: true)
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
