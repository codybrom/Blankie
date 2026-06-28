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

    /// Master-volume nudge per keystroke. 1/16 matches the macOS hardware
    /// volume keys, so ⌘↑/⌘↓ feel native next to them.
    private let volumeStep = 1.0 / 16.0

    var body: some Commands {
      // Custom View menu instead of SidebarCommands() so the toggle can bind
      // ⌘S (free in Blankie — no documents to save) rather than the fixed ⌃⌘S.
      CommandMenu("View") {
        Button("Show/Hide Sidebar") {
          NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        .keyboardShortcut(.toggleSidebar)
      }

      CommandMenu("Controls") {
        // Space mirrors the play/pause convention in music apps (Music, Spotify).
        // SwiftUI routes the binding through the focus chain, so a focused text
        // field or sound tile still gets the keystroke first.
        Button(audioManager.isGloballyPlaying ? "Pause" : "Play") {
          audioManager.togglePlayback()
        }
        .keyboardShortcut(.playPause)
        .disabled(!audioManager.hasSelectedSounds)

        Divider()

        // Next/Previous cycle the favorites list (starred presets + solo
        // sounds) — the same path CarPlay and the Now Playing remote drive.
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
          // Open the Settings pane directly on its About sub-page (sub-page
          // flag first so the pane never flashes the settings root). The pane
          // lives in the main window — reopen it if closed, or focus it.
          appState.showingSettingsAboutPage = true
          appState.showingSettingsPane = true
          openWindow(id: "main")
        } label: {
          Text("About Blankie")
        }
      }

      CommandGroup(replacing: .newItem) {
        // Reopen the real "main" Window scene. Hand-building an NSWindow +
        // NSHostingView here breaks the split view's toolbar integration
        // (merged toolbar cluster, floating sidebar).
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
        // Disabled when no preset is effectively in control: Quick Mix already
        // clears currentPreset, but solo preserves it — so gate on solo too, so
        // ⌘E never exports the hidden preset while you're hearing one sound.
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

      // Add Help menu command
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
      }
    }

    /// Exports the currently playing preset as a `.blankie` file. Lives here
    /// (rather than the Edit sheet) so ⌘E works from anywhere — the archive
    /// build is the same off-main-actor `PresetExporter` path the sheet uses.
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
