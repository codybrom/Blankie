//
//  PresetPicker.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

struct PresetPicker: View {
  @ObservedObject private var presetManager = PresetManager.shared
  @State private var showingPresetPopover = false
  @State private var newPresetName = ""
  @State private var error: Error?
  @State private var selectedPresetForEdit: Preset?
  @State private var showingCreatePreset = false

  var body: some View {
    HStack {
      Button {
        showingPresetPopover.toggle()
      } label: {
        HStack(spacing: 4) {
          Text(
            presetManager.hasCustomPresets
              ? (presetManager.currentPreset?.isDefault == true
                ? String(localized: "Blankie")
                : (presetManager.currentPreset?.name
                  ?? String(localized: "Blankie")))
              : String(localized: "Presets")
          )
          .fontWeight(.bold)
          Image(systemName: "chevron.down")
            .imageScale(.small)
        }
      }
      .buttonStyle(.plain)
      .disabled(presetManager.isLoading)
      .popover(isPresented: $showingPresetPopover, arrowEdge: .bottom) {
        if presetManager.isLoading {
          PresetLoadingView()
        } else {
          VStack(spacing: 0) {
            PresetList(
              presetManager: presetManager,
              isPresented: $showingPresetPopover,
              selectedPresetForEdit: $selectedPresetForEdit
            )
            .frame(maxWidth: 300)
            Divider()

            Button(action: {
              showingCreatePreset = true
              showingPresetPopover = false
            }) {
              Label(
                String(localized: "New Preset"), systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(8)
          }
        }
      }
    }
    .sheet(item: $selectedPresetForEdit) { preset in
      EditPresetSheet(
        preset: preset,
        isPresented: $selectedPresetForEdit
      )
    }
    .sheet(isPresented: $showingCreatePreset) {
      CreatePresetSheet(isPresented: $showingCreatePreset)
    }
  }
}

private struct PresetList: View {
  @ObservedObject var presetManager: PresetManager
  @Binding var isPresented: Bool
  @Binding var selectedPresetForEdit: Preset?
  @State private var error: Error?

  var backgroundColorForPlatform: Color {
    #if os(macOS)
      return Color(NSColor.controlBackgroundColor)
    #else
      return Color(UIColor.secondarySystemBackground)
    #endif
  }

  var body: some View {
    VStack(spacing: 0) {
      if presetManager.isLoading {
        PresetLoadingView()
      } else if !presetManager.hasCustomPresets {
        // Show empty state only if there are zero *custom* presets
        PresetEmptyState(showingNewPresetSheet: $isPresented)
      } else {
        // Custom presets
        ForEach(presetManager.presets.filter { !$0.isDefault }) { preset in
          PresetRow(
            preset: preset, isPresented: $isPresented, selectedPresetForEdit: $selectedPresetForEdit
          )
          if preset.id != presetManager.presets.last?.id {
            Divider()
          }
        }
      }
    }
    .background(backgroundColorForPlatform)
    .alert("Error", isPresented: .constant(error != nil)) {
      Button("OK") { error = nil }
    } message: {
      if let error = error {
        Text(error.localizedDescription)
      }
    }
  }
}

private struct PresetRow: View {
  let preset: Preset
  @Binding var isPresented: Bool
  @Binding var selectedPresetForEdit: Preset?
  @ObservedObject private var presetManager = PresetManager.shared
  @State private var showingEditSheet = false
  @State private var error: Error?

  var body: some View {
    HStack(spacing: 8) {
      Button(action: {
        do {
          // Exit solo mode without resuming if active
          if AudioManager.shared.soloModeSound != nil {
            AudioManager.shared.exitSoloModeWithoutResuming()
          }

          // Exit CarPlay Quick Mix if active
          if AudioManager.shared.isQuickMix {
            AudioManager.shared.exitQuickMix()
          }

          try presetManager.applyPreset(preset)
          isPresented = false
        } catch {
          self.error = error
        }
      }) {
        HStack {
          Text(preset.name)
            .foregroundStyle(.primary)

          Spacer()

          if presetManager.currentPreset?.id == preset.id {
            Image(systemName: "checkmark")
              .foregroundStyle(.blue)
          }
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      // Only show edit and delete buttons for non-default presets
      if !preset.isDefault {
        Button(action: {
          selectedPresetForEdit = preset
        }) {
          Image(systemName: "pencil")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rename Preset")
        #if os(macOS)
          .help("Rename Preset")
        #endif
        Button(action: {
          presetManager.deletePreset(preset)
        }) {
          Image(systemName: "trash")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete Preset")
        #if os(macOS)
          .help("Delete Preset")
        #endif
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .alert(
      "Error", isPresented: .constant(error != nil)
    ) {
      Button("OK") { error = nil }
    } message: {
      if let error = error {
        Text(error.localizedDescription)
      }
    }
  }
}
