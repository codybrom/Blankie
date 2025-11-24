//
//  PresetsLibraryView.swift
//  Blankie
//
//  Presets library with mood organization and grid layout
//

import SwiftUI

#if os(iOS) || os(visionOS)

  struct PresetsLibraryView: View {
    @Binding var expandPlayer: Bool
    @Binding var showingMixer: Bool
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var audioManager = AudioManager.shared
    @State private var showingCreatePreset = false
    @State private var presetToEdit: Preset?
    @State private var editMode: EditMode = .inactive

    var body: some View {
      NavigationStack {
        List {
          // Recent presets section
          if !recentPresets.isEmpty && editMode == .inactive {
            Section {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                  ForEach(recentPresets) { preset in
                    PresetGridCard(
                      preset: preset,
                      expandPlayer: $expandPlayer,
                      presetToEdit: $presetToEdit
                    )
                    .frame(width: 140)
                  }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
              }
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
            } header: {
              Text("Recent")
                .font(.title3)
                .fontWeight(.semibold)
                .textCase(nil)
                .padding(.horizontal, 16)
            }
          }

          // All presets list
          Section {
            if filteredPresets.isEmpty {
              VStack(spacing: 12) {
                Image(systemName: "rectangle.stack")
                  .font(.system(size: 48))
                  .foregroundStyle(.secondary)
                Text("No Presets")
                  .font(.headline)
                  .foregroundStyle(.secondary)
                Text("Create your first preset")
                  .font(.subheadline)
                  .foregroundStyle(.tertiary)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
              .listRowBackground(Color.clear)
            } else {
              ForEach(filteredPresets) { preset in
                PresetListRow(preset: preset, expandPlayer: $expandPlayer, presetToEdit: $presetToEdit)
                  .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                  .listRowBackground(Color.clear)
              }
              .onMove { from, to in
                movePresets(from: from, to: to)
              }
            }
          } header: {
            HStack {
              Text("All Presets")
                .font(.title3)
                .fontWeight(.semibold)
                .textCase(nil)

              Spacer()

              Button {
                withAnimation {
                  editMode = editMode == .active ? .inactive : .active
                }
              } label: {
                Text(editMode == .active ? "Done" : "Edit")
                  .font(.body)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Presets")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showingCreatePreset = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .sheet(isPresented: $showingCreatePreset) {
        CreatePresetSheet(isPresented: $showingCreatePreset)
      }
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
      }
    }

    private var recentPresets: [Preset] {
      // Get recently used presets (limit to 3)
      presetManager.presets
        .filter { !$0.isDefault }
        .prefix(3)
        .map { $0 }
    }

    private var filteredPresets: [Preset] {
      return presetManager.presets.sorted { p1, p2 in
        // Default preset last
        if p1.isDefault { return false }
        if p2.isDefault { return true }
        // Then by order
        let order1 = p1.order ?? Int.max
        let order2 = p2.order ?? Int.max
        return order1 < order2
      }
    }

    private func movePresets(from source: IndexSet, to destination: Int) {
      var updatedPresets = filteredPresets
      updatedPresets.move(fromOffsets: source, toOffset: destination)

      // Update order for all non-default presets
      for (index, var preset) in updatedPresets.enumerated() where !preset.isDefault {
        // Update the preset's order value
        preset.order = index

        // Find the index in the actual presets array and update it
        if let actualIndex = presetManager.presets.firstIndex(where: { $0.id == preset.id }) {
          presetManager.updatePresetAtIndex(actualIndex, with: preset)
        }
      }

      // Save changes
      presetManager.savePresets()
    }
  }

  // MARK: - Preset List Row

  struct PresetListRow: View {
    let preset: Preset
    @Binding var expandPlayer: Bool
    @Binding var presetToEdit: Preset?

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var artworkImage: UIImage?
    @State private var playTrigger = 0

    private var isCurrentPreset: Bool {
      presetManager.currentPreset?.id == preset.id && audioManager.soloModeSound == nil && !audioManager.isQuickMix
    }

    var body: some View {
      Button {
        playTrigger += 1
        Task {
          do {
            if audioManager.soloModeSound != nil {
              audioManager.exitSoloModeWithoutResuming()
            }
            if audioManager.isQuickMix {
              audioManager.exitQuickMix()
            }
            try presetManager.applyPreset(preset)
            // Expand player to show now playing
            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
              expandPlayer = true
            }
          } catch {
            print("Error applying preset: \(error)")
          }
        }
      } label: {
        HStack(spacing: 16) {
          // Squircle artwork
          ZStack {
            Group {
              if let image = artworkImage {
                Image(uiImage: image)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              } else {
                Rectangle()
                  .fill(Color.secondary.opacity(0.2))
                  .overlay {
                    BrandedBlankieIcon(size: 24)
                  }
              }
            }

          }
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

          // Info
          VStack(alignment: .leading, spacing: 2) {
            Text(preset.displayName)
              .font(.body)
              .fontWeight(.medium)
              .foregroundColor(.primary)

            if let moods = preset.moods, !moods.isEmpty {
              Text(moods.map { $0.displayName }.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              Text("\(preset.soundStates.count) sounds")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          Spacer(minLength: 0)

          // Edit button (just 3 dots)
          if !preset.isDefault {
            Button {
              presetToEdit = preset
            } label: {
              Image(systemName: "ellipsis")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playTrigger)
      .task {
        artworkImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
      }
    }
  }

  // MARK: - Preset Grid Card

  struct PresetGridCard: View {
    let preset: Preset
    @Binding var expandPlayer: Bool
    @Binding var presetToEdit: Preset?

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var artworkImage: UIImage?
    @State private var playTrigger = 0

    private var isCurrentPreset: Bool {
      presetManager.currentPreset?.id == preset.id && audioManager.soloModeSound == nil && !audioManager.isQuickMix
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        // Artwork
        Button {
          playTrigger += 1
          Task {
            do {
              if audioManager.soloModeSound != nil {
                audioManager.exitSoloModeWithoutResuming()
              }
              if audioManager.isQuickMix {
                audioManager.exitQuickMix()
              }
              try presetManager.applyPreset(preset)
              // Expand player to show now playing
              withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                expandPlayer = true
              }
            } catch {
              print("Error applying preset: \(error)")
            }
          }
        } label: {
          ZStack {
            Group {
              if let image = artworkImage {
                Image(uiImage: image)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              } else {
                Rectangle()
                  .fill(Color.secondary.opacity(0.2))
                  .overlay {
                    BrandedBlankieIcon(size: 80)
                  }
              }
            }

          }
          .frame(height: 160)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playTrigger)

        // Title and info
        VStack(alignment: .leading, spacing: 4) {
          Text(preset.displayName)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .lineLimit(1)

          if let moods = preset.moods, !moods.isEmpty {
            Text(moods.map { $0.displayName }.joined(separator: ", "))
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          } else {
            Text("\(preset.soundStates.count) sounds")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .padding(.top, 8)

        // Actions
        if !preset.isDefault {
          Button {
            presetToEdit = preset
          } label: {
            Image(systemName: "ellipsis")
              .font(.caption)
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .buttonStyle(.plain)
          .padding(.top, 4)
        }
      }
      .task {
        artworkImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
      }
    }
  }

  // MARK: - Mood Filter Pill

  struct MoodFilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var selectionTrigger = 0

    var body: some View {
      Button {
        selectionTrigger += 1
        action()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: icon)
            .font(.caption)
          Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
          isSelected ?
            AnyShapeStyle(.tint) :
            AnyShapeStyle(.quaternary),
          in: Capsule()
        )
        .foregroundColor(isSelected ? .white : .primary)
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.selection, trigger: selectionTrigger)
    }
  }

  #Preview {
    PresetsLibraryView(
      expandPlayer: .constant(false),
      showingMixer: .constant(false)
    )
  }

#endif
