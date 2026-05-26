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
          #if os(iOS)
            // Trailing alignment looks right on iOS; on macOS it renders the
            // prompt and value at the same time, so leave the default there.
            .multilineTextAlignment(.trailing)
          #endif
          .onChange(of: presetName) { _, _ in
            applyChangesInstantly()
          }
      }

      // Creator field (only for non-default presets)
      if !preset.isDefault {
        LabeledContent("Creator") {
          TextField("Optional", text: $creatorName)
            #if os(iOS)
              .multilineTextAlignment(.trailing)
            #endif
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
      // Per-preset view mode: Default falls back to the app-wide setting.
      // macOS has a single grid layout, so the override is meaningless there.
      #if !os(macOS)
        Picker(
          "View Mode",
          selection: Binding<PresetViewModeSelection>(
            get: { PresetViewModeSelection(viewModeOverride) },
            set: { viewModeOverride = $0.asOptional }
          )
        ) {
          Text("Default", comment: "Follow app-wide view-mode setting").tag(
            PresetViewModeSelection.useDefault)
          Text("Grid", comment: "Tile/grid view mode").tag(PresetViewModeSelection.grid)
          Text("List", comment: "List view mode").tag(PresetViewModeSelection.list)
        }
        .onChange(of: viewModeOverride) { _, _ in
          applyChangesInstantly()
        }
      #endif

      // Accent Color
      Toggle("Accent Color", isOn: $useCustomTheme)

      if useCustomTheme {
        #if os(macOS)
          // macOS uses the circle swatches (no System swatch — the toggle above
          // already handles the off state).
          AccentColorCirclePicker(selectedColor: $accentColor, allowSystem: false)
        #else
          SpectrumColorPicker(selectedColor: $accentColor)
            .padding(.vertical, 4)
        #endif
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
            .accessibilityLabel("Remove Artwork")
          }

          Button {
            showingImagePicker = true
          } label: {
            artworkPreview
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Choose Artwork")
        }
      }

      // Background blur override. Off = follow the app-wide default; on reveals
      // a slider, mirroring the Accent Color toggle above. Persist the slider
      // only on drag-end so we don't run the full preset save on every frame.
      // The macOS window doesn't use a blurred backdrop, so hide this there.
      #if !os(macOS)
        Toggle("Custom Background Blur", isOn: $useCustomBlur)
          .onChange(of: useCustomBlur) { _, _ in
            applyChangesInstantly()
          }

        if useCustomBlur {
          Slider(
            value: $blurOverride,
            in: 0...20,
            step: 5,
            label: {
              Text("Background Blur", comment: "Accessibility label for background blur slider")
            },
            minimumValueLabel: {
              // Small dot -> large dot encodes "less -> more" without text.
              Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            },
            maximumValueLabel: {
              Image(systemName: "circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            },
            onEditingChanged: { editing in
              if !editing {
                applyChangesInstantly()
              }
            }
          )
          .padding(.vertical, 4)
        }
      #endif

      // Animated artwork editing is iOS-only; hide it on macOS.
      #if !os(macOS)
        AnimatedArtworkPicker(
          artwork: $animatedArtwork,
          staticArtworkPath: $staticArtworkPath,
          onChange: { applyChangesInstantly() }
        )
      #endif
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
            // macOS has no editMode, so `.onMove` below is inert. Make each row
            // drag-reorderable with onDrag/onDrop instead, carrying the row's
            // index and routing through `moveSound` (which also persists).
            let rowIndex = orderedSelectedSounds.firstIndex(where: { $0.id == sound.id }) ?? 0
            HStack(spacing: 12) {
              Image(systemName: sound.systemIconName)
                .font(.title3)
                .foregroundColor(activeAccentColor)
                .frame(width: 24)

              Text(sound.title)
                .font(.body)

              Spacer()

              Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
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
    } footer: {
      if !selectedSounds.isEmpty {
        Text("Drag sounds to reorder how they appear in the preset")
          .font(.caption)
      }
    }
    #if os(iOS)
      .environment(\.editMode, .constant(.active))
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
          // toOffset inserts *before* the index, so dropping below the source
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
      }
    }
  }
}
