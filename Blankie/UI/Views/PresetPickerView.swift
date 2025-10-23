import SwiftUI
import TipKit

struct PresetPickerRow: View {
  let preset: Preset
  let isEditMode: Bool
  let onSelection: (() -> Void)?
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @Environment(\.dismiss) private var dismiss

  init(preset: Preset, isEditMode: Bool, onSelection: (() -> Void)? = nil) {
    self.preset = preset
    self.isEditMode = isEditMode
    self.onSelection = onSelection
  }

  var body: some View {
    Button {
      // Exit solo mode if active, then apply the preset
      Task {
        do {
          // Exit solo mode without resuming previous sounds if active
          // This prevents the previous preset from briefly playing
          if audioManager.soloModeSound != nil {
            audioManager.exitSoloModeWithoutResuming()
          }

          // Exit Quick Mix if we're in it
          if audioManager.isQuickMix {
            audioManager.exitQuickMix()
          }

          try presetManager.applyPreset(preset)

          // Mark that user has switched presets for onboarding tracking
          OnboardingManager.shared.markPresetSwitched()

          dismiss()
          onSelection?()
        } catch {
          print("Error applying preset: \(error)")
        }
      }
    } label: {
      HStack {
        HStack(spacing: 8) {
          // Special badge for default preset
          if preset.isDefault {
            Image(systemName: "square.stack")
              .foregroundColor(.accentColor)
          }

          Text(preset.displayName)
            .foregroundColor(.primary)
        }

        Spacer()

        // Only show checkmark if not in solo mode AND this is the current preset
        let isSoloModeActive = audioManager.soloModeSound != nil
        let isCurrentPreset = presetManager.currentPreset?.id == preset.id

        if !isSoloModeActive && isCurrentPreset {
          Image(systemName: "checkmark")
            .foregroundColor(.accentColor)
        }
      }
    }
  }
}

struct PresetPickerView: View {
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var onboardingManager = OnboardingManager.shared
  @State private var showingNewPresetSheet = false
  @State private var newPresetName = ""
  @State private var presetToDelete: Preset?
  @State private var isEditMode = false
  @State private var editingPresets: [Preset] = []
  @Environment(\.dismiss) private var dismiss

  // TipKit tips
  private let createFirstPresetTip = CreateFirstPresetTip()
  private let switchPresetsTip = SwitchPresetsTip()

  private var sortedCustomPresets: [Preset] {
    presetManager.presets
      .filter { !$0.isDefault }
      .sorted {
        let order1 = $0.order ?? Int.max
        let order2 = $1.order ?? Int.max
        return order1 < order2
      }
  }

  private func deletePresets(at offsets: IndexSet) {
    // Remove from editing array
    editingPresets.remove(atOffsets: offsets)
  }

  private func movePresets(from source: IndexSet, to destination: Int) {
    print("🎵 PresetPickerView: Moving preset from \(source) to \(destination)")
    // Work with the editing copy
    editingPresets.move(fromOffsets: source, toOffset: destination)

    // Log the new order
    for (index, preset) in editingPresets.enumerated() {
      print("🎵 PresetPickerView: Position \(index): \(preset.name)")
    }
  }

  private func startEditing() {
    // Create a copy of custom presets sorted by order for editing
    editingPresets = sortedCustomPresets
    isEditMode = true
  }

  private func cancelEditing() {
    isEditMode = false
    editingPresets = []
  }

  private func saveEditing() {
    // First, handle deletions by finding presets that are no longer in editingPresets
    let editingIds = Set(editingPresets.map { $0.id })
    let customPresets = presetManager.presets.filter { !$0.isDefault }
    let deletedPresets = customPresets.filter { !editingIds.contains($0.id) }

    // Delete removed presets
    for preset in deletedPresets {
      presetManager.deletePreset(preset)
    }

    // Create a map of updated presets with their new order values
    var updatedPresetsMap: [UUID: Preset] = [:]

    // Update order property for each preset in editingPresets
    for (index, editedPreset) in editingPresets.enumerated() {
      var updatedPreset = editedPreset
      updatedPreset.order = index
      print("🎵 PresetPickerView: Setting order \(index) for preset '\(updatedPreset.name)'")
      updatedPresetsMap[updatedPreset.id] = updatedPreset
    }

    // Get all presets and update only the ones we edited
    var allPresets = presetManager.presets
    for index in 0 ..< allPresets.count {
      if let updatedPreset = updatedPresetsMap[allPresets[index].id] {
        allPresets[index] = updatedPreset
        print(
          "🎵 PresetPickerView: Updated preset '\(updatedPreset.name)' at index \(index) with order \(updatedPreset.order ?? -1)"
        )
      }
    }

    // Update all presets at once
    presetManager.setPresets(allPresets)

    // Save the updated order
    presetManager.savePresets()

    isEditMode = false
    editingPresets = []
  }

  var body: some View {
    NavigationView {
      List {
        // Show tip for creating first preset if no custom presets exist
        if !presetManager.hasCustomPresets {
          TipView(createFirstPresetTip, arrowEdge: .top) { action in
            if action.id == "create" {
              showingNewPresetSheet = true
            }
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }

        if presetManager.isLoading {
          // Loading view
          HStack {
            Spacer()
            ProgressView("Loading Presets...")
            Spacer()
          }
          .padding()
        } else if presetManager.presets.isEmpty {
          // Empty state
          HStack {
            Spacer()
            VStack(spacing: 12) {
              Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

              Text("No Custom Presets", comment: "Empty state title for presets")
                .font(.headline)

              Text(
                "Save your current sound configuration as a preset to quickly access it later.",
                comment: "Empty state description for presets"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: 250)
            Spacer()
          }
          .listRowBackground(Color.clear)
        } else {
          // Solo mode indicator (if active)
          if let soloSound = audioManager.soloModeSound {
            HStack {
              HStack(spacing: 8) {
                Image(systemName: "headphones.circle.fill")
                  .foregroundColor(.accentColor)
                Text("Solo Mode - \(soloSound.title)")
                  .foregroundColor(.secondary)
              }

              Spacer()

              Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
            }
            .listRowBackground(Color.secondary.opacity(0.1))
          }

          // Quick Mix mode
          if audioManager.isQuickMix {
            // Quick Mix indicator (if active)
            HStack {
              HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                  .foregroundColor(.accentColor)
                Text("Quick Mix")
                  .foregroundColor(.secondary)
              }

              Spacer()

              Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
            }
            .listRowBackground(Color.secondary.opacity(0.1))
          } else {
            // Quick Mix button (if not active)
            Button {
              Task { @MainActor in
                audioManager.enterQuickMix()
                // Mark that user has used Quick Mix
                OnboardingManager.shared.markQuickMixUsed()
                dismiss()
              }
            } label: {
              HStack {
                HStack(spacing: 8) {
                  Image(systemName: "square.grid.2x2")
                    .foregroundColor(.accentColor)
                  Text("Quick Mix")
                    .foregroundColor(.primary)
                }

                Spacer()
              }
            }
          }

          // Default preset (not reorderable)
          if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
            PresetPickerRow(preset: defaultPreset, isEditMode: isEditMode) {
              dismiss()
            }
          }

          // Custom presets (reorderable)
          let customPresets = isEditMode ? editingPresets : sortedCustomPresets

          ForEach(customPresets) { preset in
            PresetPickerRow(preset: preset, isEditMode: isEditMode) {
              dismiss()
            }
            .deleteDisabled(!isEditMode || preset.isDefault)
          }
          .onDelete(perform: isEditMode ? deletePresets : nil)
          .onMove(perform: isEditMode ? movePresets : nil)
        }
      }
      .navigationTitle("Presets")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if presetManager.hasCustomPresets {
              Button {
                if isEditMode {
                  cancelEditing()
                } else {
                  startEditing()
                }
              } label: {
                Text(isEditMode ? "Cancel" : "Edit", comment: "Edit mode toggle button")
              }
            }
          }

          ToolbarItem(placement: .primaryAction) {
            if isEditMode {
              Button("Done") {
                saveEditing()
              }
              .fontWeight(.semibold)
            } else {
              Button {
                showingNewPresetSheet = true
              } label: {
                Label("New Preset", systemImage: "plus")
              }
            }
          }
        }
      #if os(iOS)
        .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
      #endif
        .sheet(isPresented: $showingNewPresetSheet) {
          CreatePresetSheet(isPresented: $showingNewPresetSheet)
        }
        .alert(
          "Delete Preset",
          isPresented: .init(
            get: { presetToDelete != nil },
            set: { if !$0 { presetToDelete = nil } }
          )
        ) {
          Button("Cancel", role: .cancel) {
            presetToDelete = nil
          }

          Button("Delete", role: .destructive) {
            if let preset = presetToDelete {
              Task {
                presetManager.deletePreset(preset)
                presetToDelete = nil
              }
            }
          }
        } message: {
          if let preset = presetToDelete {
            Text(
              "Are you sure you want to delete '\(preset.name)'? This action cannot be undone.",
              comment: "Delete preset confirmation message"
            )
          }
        }
        .onDisappear {
          // Cancel editing if view is dismissed (e.g., by swiping)
          if isEditMode {
            cancelEditing()
          }
        }
    }
  }
}

// Preview Provider
struct PresetPickerView_Previews: PreviewProvider {
  static var previews: some View {
    PresetPickerView()
  }
}
