//
//  BlankieToolbar.swift
//  Blankie
//
//  Created by Cody Bromley on 1/11/25.
//

import SwiftUI

#if os(macOS)
  struct BlankieToolbar: ToolbarContent {
    @Binding var showingAbout: Bool
    @Binding var showingShortcuts: Bool
    @Binding var showingNewPresetPopover: Bool
    @Binding var presetName: String

    @ObservedObject private var appState = AppState.shared
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared

    var body: some ToolbarContent {
      ToolbarItem(placement: .primaryAction) {
        if !PresetManager.shared.presets.isEmpty {
          PresetPicker()
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Manage Sounds") {
            appState.showingManageSounds = true
          }
          .keyboardShortcut(.manageSounds)

          Divider()

          Button("About Blankie") {
            showingAbout = true
            appState.isAboutViewPresented = true
          }

          Button("Keyboard Shortcuts") {
            showingShortcuts = true
          }
          .keyboardShortcut(.keyboardShortcuts)

          SettingsLink {
            Text(
              LocalizedStringResource(
                "menu.preferences", defaultValue: "Preferences..."))
          }
          .keyboardShortcut(.preferences)

          Divider()

          Button("Quit Blankie") {
            audioManager.pauseAll()
            exit(0)
          }
          .keyboardShortcut(.quit)
        } label: {
          Image(systemName: "line.3.horizontal")
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("Menu"))
      }
    }
  }
#endif

// Add an iOS-compatible version that does nothing
#if os(iOS) || os(visionOS)
  struct BlankieToolbar: ToolbarContent {
    @Binding var showingAbout: Bool
    @Binding var showingShortcuts: Bool
    @Binding var showingNewPresetPopover: Bool
    @Binding var presetName: String

    var body: some ToolbarContent {
      // For iOS, we need to provide at least one item
      ToolbarItem(placement: .navigationBarTrailing) {
        EmptyView()
      }
    }
  }
#endif
