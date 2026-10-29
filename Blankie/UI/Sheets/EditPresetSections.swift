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

// MARK: - Basic Details Section (Name, Creator, Favorite, Artwork)

extension EditPresetSheet {
  var basicDetailsSection: some View {
    PresetDetailsSection(
      presetName: $presetName,
      creatorName: $creatorName,
      artworkData: $artworkData,
      showingImagePicker: $showingImagePicker,
      animatedArtwork: $animatedArtwork,
      staticArtworkPath: $staticArtworkPath,
      starToken: starToken,
      accent: activeAccentColor,
      aiSoundTitles: orderedSelectedSounds.map(\.localizedTitle),
      // A typed name is settled, so sparkles only fills an empty one here.
      sparklesOnlyWhenEmpty: true,
      onEdited: { applyChangesInstantly() },
      onRemoveArtwork: { artworkId = nil },
      isGeneratingName: $isGeneratingName
    )
  }

  var activeAccentColor: Color {
    if useCustomTheme {
      return accentColor ?? globalSettings.customAccentColor ?? .accentColor
    } else {
      return globalSettings.customAccentColor ?? .accentColor
    }
  }
}

// MARK: - Visuals Section (View Mode, Accent Color)

extension EditPresetSheet {
  var visualsSection: some View {
    PresetThemeSection(
      useCustomViewMode: $useCustomViewMode,
      viewModeOverride: $viewModeOverride,
      useCustomTheme: $useCustomTheme,
      accentColor: $accentColor,
      onEdited: { applyChangesInstantly() }
    )
  }
}

// MARK: - Sounds Section (Reorderable)

extension EditPresetSheet {
  var soundsSection: some View {
    Section {
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          // Reads as a navigation row: plain label, count, then a gray chevron
          // (the button would otherwise tint all three with the accent).
          HStack(spacing: 8) {
            LabeledContent("Choose Sounds", value: "\(selectedSounds.count)")
              .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Color(.tertiaryLabel))
              .accessibilityHidden(true)
          }
        }
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          LabeledContent("Choose Sounds", value: "\(selectedSounds.count)")
        }
      #endif

      if selectedSounds.isEmpty {
        Text("No sounds selected")
          .foregroundStyle(.secondary)
          .font(.subheadline)
      } else {
        ForEach(orderedSelectedSounds) { sound in
          #if os(iOS)
            NavigationLink(value: SoundEditDestination(fileName: sound.fileName)) {
              HStack(spacing: 8) {
                Label {
                  Text(sound.localizedTitle)
                } icon: {
                  Image(systemName: sound.systemIconName)
                    .foregroundStyle(.primary)
                }

                SoundCreditInfoButton(sound: sound, accent: activeAccentColor)

                Spacer()

                // Per-row reorder affordance.
                Image(systemName: "line.3.horizontal")
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
            }
          #else
            // macOS has no editMode, so `.onMove` below is inert. Rows reorder via
            // onDrag/onDrop, carrying the row's index through `moveSound` (which persists).
            let rowIndex = orderedSelectedSounds.firstIndex(where: { $0.id == sound.id }) ?? 0
            HStack(spacing: 8) {
              Label {
                Text(sound.localizedTitle)
              } icon: {
                Image(systemName: sound.systemIconName)
                  .foregroundStyle(.primary)
              }

              SoundCreditInfoButton(sound: sound, accent: activeAccentColor)

              Spacer()

              Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onDrag {
              NSItemProvider(object: String(rowIndex) as NSString)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers in
              handleMacSoundDrop(providers, to: rowIndex)
            }
          #endif
        }
        .onMove { from, to in
          moveSound(from: from, to: to)
        }
      }
    } header: {
      Text("Sounds")
    }
    #if os(iOS)
      .environment(\.editMode, .constant(.active))
    #endif
  }

  /// Single source of truth for selected-sound ordering, so the displayed
  /// order and the saved order can never diverge.
  var orderedSelectedFileNames: [String] {
    // Keep the existing order, filtered to currently selected sounds
    let validOrder = soundOrder.filter { selectedSounds.contains($0) }
    // Append any newly selected sounds that aren't in the order yet
    let newSounds = selectedSounds.filter { !validOrder.contains($0) }
    return validOrder + newSounds.sorted()
  }

  var orderedSelectedSounds: [Sound] {
    orderedSelectedFileNames.compactMap { fileName in
      audioManager.sounds.first(where: { $0.fileName == fileName })
    }
  }

  func moveSound(from source: IndexSet, to destination: Int) {
    var currentOrder = orderedSelectedSounds.map { $0.fileName }
    currentOrder.move(fromOffsets: source, toOffset: destination)

    soundOrder = currentOrder

    applyChangesInstantly(skipRefresh: true)
  }

  #if os(macOS)
    /// Reads the dragged row's index from the provider and reorders onto the
    /// dropped-on row. Bridges the macOS drag-and-drop index pair into the
    /// `move(fromOffsets:toOffset:)` semantics `moveSound` expects.
    func handleMacSoundDrop(_ providers: [NSItemProvider], to destination: Int) -> Bool {
      guard let provider = providers.first else { return false }
      provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let string = object as? String, let source = Int(string) else { return }
        DispatchQueue.main.async {
          guard source != destination else { return }
          // toOffset inserts before the index, so dropping below the source
          // needs +1 to land after the target row.
          let target = source < destination ? destination + 1 : destination
          moveSound(from: IndexSet(integer: source), to: target)
        }
      }
      return true
    }
  #endif
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
        // The sheet's accent tint overrides the destructive role's color in
        // macOS grouped forms. Destructive reads red on both platforms.
        .foregroundStyle(.red)
      }
    }
  }
}
