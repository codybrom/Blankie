//
//  AppCommands.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

#if os(macOS)
  struct AppCommands: Commands {
    @Binding var showingShortcuts: Bool
    @Binding var hasWindow: Bool
    @StateObject private var appState = AppState.shared
    @State private var audioManager = AudioManager.shared
    @Environment(\.openWindow) private var openWindow

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
        Button(audioManager.isGloballyPlaying ? "Pause" : "Play") {
          audioManager.togglePlayback()
        }
        .disabled(!audioManager.hasSelectedSounds)
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
  }
#endif
