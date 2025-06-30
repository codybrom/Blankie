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

    @State var showScrollIndicator = false

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

            // Theme Color
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("Theme Color")
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
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(AccentColor.allCases.filter { $0 != .system }, id: \.self) { color in
              colorPickerItem(for: color)
                .id(color)  // Add ID for ScrollViewReader
            }
          }
          .padding(.horizontal, 20)  // Increased padding to prevent clipping
          .padding(.vertical, 2)  // Add vertical padding inside ScrollView
          .padding(.bottom, 10)
        }
        .scrollIndicators(.visible, axes: .horizontal)  // Always show horizontal indicator
        .scrollIndicatorsFlash(trigger: showScrollIndicator)  // Flash when triggered
        .onAppear {
          // Find the currently selected color and scroll to it
          if let currentColor = AccentColor.allCases.first(where: {
            $0.color == globalSettings.customAccentColor
          }) {
            // Use a slight delay to prevent visual glitches
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              proxy.scrollTo(currentColor, anchor: .center)
            }
          }
          // Flash indicators on appear to show it's scrollable
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showScrollIndicator.toggle()
          }
        }
      }
      .padding(.vertical, 4)
    }

    @ViewBuilder
    func colorPickerItem(for color: AccentColor) -> some View {
      let isSelected = globalSettings.customAccentColor == color.color

      Circle()
        .fill(color.color ?? .accentColor)
        .frame(width: 44, height: 44)
        .overlay(
          Circle()
            .strokeBorder(
              isSelected ? Color.primary : Color.gray.opacity(0.3),
              lineWidth: isSelected ? 3 : 1
            )
        )
        .overlay(
          isSelected
            ? Image(systemName: "checkmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.white)
            : nil
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)  // Reduced scale to prevent clipping
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            globalSettings.setAccentColor(color.color)
          }
        }
    }

  }
#endif
