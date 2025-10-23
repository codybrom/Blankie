//
//  ViewSettingsSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 1/7/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct ViewSettingsSheet: View {
    @Binding var isPresented: Bool
    @Binding var showingListView: Bool
    @Binding var hideInactiveSounds: Bool

    @ObservedObject var globalSettings = GlobalSettings.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var presetManager = PresetManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
      NavigationStack {
        Form {
          Section {
            // Options that don't apply in solo mode or Quick Mix mode
            if audioManager.soloModeSound == nil && !audioManager.isQuickMix {
              // View Mode
              Picker("View Mode", selection: $showingListView) {
                Text("Grid").tag(false)
                Text("List").tag(true)
              }
              .pickerStyle(.segmented)

              // Icon Size - only show in grid view and only on macOS
              #if os(macOS)
                if !showingListView {
                  Picker(
                    "Icon Size",
                    selection: Binding(
                      get: { globalSettings.iconSize },
                      set: { globalSettings.setIconSize($0) }
                    )
                  ) {
                    Text("Small").tag(IconSize.small)
                    Text("Medium").tag(IconSize.medium)
                    Text("Large").tag(IconSize.large)
                  }
                  .pickerStyle(.menu)
                }
              #endif

              // Toggles
              Toggle(
                "Show Labels",
                isOn: Binding(
                  get: { globalSettings.showSoundNames },
                  set: { globalSettings.setShowSoundNames($0) }
                )
              )

              #if os(macOS)
                Toggle(
                  "Show Inactive Sounds",
                  isOn: Binding(
                    get: { !hideInactiveSounds },
                    set: { hideInactiveSounds = !$0 }
                  )
                )
              #endif
            }

            // Progress Borders - show in solo mode and grid view, but not in Quick Mix
            if !audioManager.isQuickMix
              && (audioManager.soloModeSound != nil || !showingListView)
            {
              Toggle(
                "Show Progress Borders",
                isOn: Binding(
                  get: { globalSettings.showProgressBorder },
                  set: { globalSettings.setShowProgressBorder($0) }
                )
              )
            }

            // Appearance
            Picker(
              "Appearance",
              selection: Binding(
                get: { globalSettings.appearance },
                set: { globalSettings.setAppearance($0) }
              )
            ) {
              ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Text(mode.localizedName).tag(mode)
              }
            }
            .pickerStyle(.menu)

            // Accent Color
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("Accent Color")
                  .foregroundColor(.primary)
                Spacer()
              }

              colorPickerSection
            }
          }
        }
        .padding(.top, -30)
        .navigationTitle("View Settings")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              dismiss()
            }
          }
        }
      }
      .onChange(of: showingListView) { _, newValue in
        globalSettings.setShowingListView(newValue)
      }
      .preferredColorScheme(
        globalSettings.appearance == .system
          ? nil
          : (globalSettings.appearance == .dark ? .dark : .light)
      )
    }

    // MARK: - Color Picker Section

    @ViewBuilder
    var colorPickerSection: some View {
      SpectrumColorPicker(selectedColor: $globalSettings.customAccentColor)
        .padding(.vertical, 4)
        .onChange(of: globalSettings.customAccentColor) { _, newColor in
          globalSettings.setAccentColor(newColor)
        }
    }
  }
#endif
