//
//  PresetThemeSection.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/26.
//

import SwiftUI

/// Shared "Customize Theme" card for the preset editors (Edit Preset and New
/// Preset). Every override follows the same shape: a toggle to opt in, with
/// the control revealed below it (so the pickers don't need a "Default"
/// option — toggled off = follow the app-wide setting). Edit persists
/// instantly via `onEdited`; New Preset reads the bindings when Create runs.
struct PresetThemeSection: View {
  @Binding var useCustomViewMode: Bool
  @Binding var viewModeOverride: PresetViewMode?
  @Binding var useCustomTheme: Bool
  @Binding var accentColor: Color?
  @Binding var useCustomBlur: Bool
  @Binding var blurOverride: Double
  var onEdited: (() -> Void)?

  @ObservedObject private var globalSettings = GlobalSettings.shared

  var body: some View {
    Section {
      content
    } header: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Customize Theme")
        Text("Overrides your default theme settings when this preset is active")
          .font(.caption)
          .textCase(.none)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    Group {
      // Per-preset view mode. macOS has a single grid layout, so the override
      // is meaningless there.
      #if !os(macOS)
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Customize View Mode", isOn: $useCustomViewMode)

          if useCustomViewMode {
            Picker(
              "Customize View Mode",
              selection: Binding<PresetViewMode>(
                get: { viewModeOverride ?? (globalSettings.showingListView ? .list : .grid) },
                set: { viewModeOverride = $0 }
              )
            ) {
              Text("Grid").tag(PresetViewMode.grid)
              Text("List").tag(PresetViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
          }
        }
        .onChange(of: useCustomViewMode) { _, enabled in
          // Seed with the effective value so enabling doesn't flip the layout.
          viewModeOverride = enabled ? (globalSettings.showingListView ? .list : .grid) : nil
          onEdited?()
        }
        .onChange(of: viewModeOverride) { _, _ in
          onEdited?()
        }
      #endif

      // Accent Color. The toggle and picker share one list row so no separator
      // (or extra row padding) appears between them when the picker is shown.
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Customize Accent Color", isOn: $useCustomTheme)

        if useCustomTheme {
          // Same spectrum slider as Settings on both platforms.
          SpectrumColorPicker(selectedColor: $accentColor)
        }
      }

      // Background blur override (On = the single app-wide blur value). The
      // macOS window doesn't use a blurred backdrop, so hide this there.
      #if !os(macOS)
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Customize Background Blur", isOn: $useCustomBlur)

          if useCustomBlur {
            Picker(
              "Customize Background Blur",
              selection: Binding<Double>(
                get: { blurOverride },
                set: { blurOverride = $0 }
              )
            ) {
              Text("No Blur").tag(0.0)
              Text("Blurred").tag(defaultBackgroundBlurRadius)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
          }
        }
        .onChange(of: useCustomBlur) { _, _ in
          onEdited?()
        }
        .onChange(of: blurOverride) { _, _ in
          onEdited?()
        }
      #endif
    }
  }
}
