//
//  AppCommands.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

#if os(macOS)
  import AppKit
  import UniformTypeIdentifiers
  import os

  struct AppCommands: Commands {
    @Binding var showingShortcuts: Bool
    @Binding var hasWindow: Bool
    @StateObject private var appState = AppState.shared
    @State private var audioManager = AudioManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var globalSettings = GlobalSettings.shared
    @Environment(\.openWindow) private var openWindow

    /// Master-volume step per keystroke. 1/16 matches the macOS hardware volume keys.
    private let volumeStep = 1.0 / 16.0

    var body: some Commands {
      // Replaces the View menu's sidebar item so the toggle can use ⌘S (Blankie has no
      // documents to save). SidebarCommands() fixes it to ⌃⌘S, and a CommandMenu("View")
      // would add a second View menu.
      CommandGroup(replacing: .sidebar) {
        Button("Show/Hide Sidebar") {
          NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        .keyboardShortcut(.toggleSidebar)
      }

      CommandMenu("Controls") {
        // Space follows the music-app play/pause convention. The binding routes through
        // the focus chain, so a focused text field or sound tile gets the key first.
        Button(audioManager.isGloballyPlaying ? "Pause" : "Play") {
          audioManager.togglePlayback()
        }
        .keyboardShortcut(.playPause)
        .disabled(!audioManager.hasSelectedSounds)

        Divider()

        // Cycles favorites (starred presets and solo sounds), the same path CarPlay
        // and the Now Playing remote use.
        Button("Next Favorite") {
          audioManager.navigateToNextPreset()
        }
        .keyboardShortcut(.nextFavorite)
        .disabled(!audioManager.canNavigateNextPrevious)

        Button("Previous Favorite") {
          audioManager.navigateToPreviousPreset()
        }
        .keyboardShortcut(.previousFavorite)
        .disabled(!audioManager.canNavigateNextPrevious)

        Divider()

        Button("Volume Up") {
          globalSettings.setVolume(globalSettings.volume + volumeStep)
        }
        .keyboardShortcut(.volumeUp)
        .disabled(globalSettings.volume >= 1.0)

        Button("Volume Down") {
          globalSettings.setVolume(globalSettings.volume - volumeStep)
        }
        .keyboardShortcut(.volumeDown)
        .disabled(globalSettings.volume <= 0.0)
      }

      CommandGroup(replacing: .appInfo) {
        Button {
          // Sub-page flag first so the pane doesn't flash the settings root. The pane
          // lives in the main window, which openWindow reopens or focuses.
          appState.showingSettingsAboutPage = true
          appState.showingSettingsPane = true
          openWindow(id: "main")
        } label: {
          Text("About Blankie")
        }
      }

      CommandGroup(replacing: .newItem) {
        // Reopens the "main" Window scene. A hand-built NSWindow breaks the split
        // view's toolbar integration.
        Button("New Window") {
          openWindow(id: "main")
        }
        .disabled(hasWindow)
        .keyboardShortcut(.newWindow)

        Divider()

        Button("Import") {
          appState.showingImport = true
        }
        .keyboardShortcut(.importFile)

        Button("Export Current Preset…") {
          Task { await exportCurrentPreset() }
        }
        .keyboardShortcut(.exportPreset)
        // Solo keeps currentPreset set, so ⌘E is also disabled in solo to avoid
        // exporting a preset you aren't hearing.
        .disabled(presetManager.currentPreset == nil || audioManager.soloModeSound != nil)

        Button("Manage Sounds") {
          appState.showingManageSounds = true
        }
        .keyboardShortcut(.manageSounds)
      }

      #if DEBUG
        CommandMenu("Debug") {
          Button("Show Onboarding") {
            appState.showingOnboarding = true
          }
        }
      #endif

      CommandGroup(replacing: .help) {
        Button("Keyboard Shortcuts") {
          showingShortcuts = true
        }
        .keyboardShortcut(.keyboardShortcuts)

        Button("Blankie Help") {
          if let url = URL(string: "https://blankie.rest/faq") {
            NSWorkspace.shared.open(url)
          }
        }

        Button("Privacy Policy") {
          if let url = URL(string: "https://blankie.rest/privacy") {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }

    /// Exports the current preset as a `.blankie` file so ⌘E works from anywhere.
    /// Uses the same off-main-actor `PresetExporter` path as the Edit sheet.
    @MainActor
    private func exportCurrentPreset() async {
      guard let preset = presetManager.currentPreset else { return }

      // The save panel is the user's step, so it runs before any await.
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.blankie]
      panel.nameFieldStringValue =
        "\(preset.name).blankie"
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let destination = panel.url else { return }

      do {
        let builtURL = try await PresetExporter.shared.createArchive(for: preset)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: builtURL, to: destination)
        try? FileManager.default.removeItem(at: builtURL)
      } catch {
        Logger.ui.error("Preset export failed: \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = String(localized: "Export Failed")
        alert.informativeText =
          (error as? PresetExporter.ExportError)?.errorDescription
          ?? String(
            localized: "Couldn't export this preset. Please try again.",
            comment: "Alert message shown when exporting a preset fails for an unexpected reason.")
        alert.runModal()
      }
    }
  }
#endif
