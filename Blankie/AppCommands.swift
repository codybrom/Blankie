//
//  AppCommands.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

#if os(macOS)
  struct AppCommands: Commands {
    @Binding var showingAbout: Bool
    @Binding var showingShortcuts: Bool
    @Binding var hasWindow: Bool
    @StateObject private var appState = AppState.shared
    @StateObject private var audioManager = AudioManager.shared

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
          showingAbout = true
          appState.isAboutViewPresented = true
        } label: {
          Text("About Blankie")
        }
      }

      CommandGroup(replacing: .newItem) {
        Button("New Window") {
          if !hasWindow {
            let controller = NSWindowController(
              window: NSWindow(
                contentRect: WindowDefaults.defaultFrame,
                styleMask: WindowDefaults.styleMask,
                backing: .buffered,
                defer: false
              )
            )

            if let window = controller.window {
              WindowDefaults.configureWindow(window)

              let contentView = WindowDefaults.defaultContentView(
                showingAbout: $showingAbout,
                showingShortcuts: $showingShortcuts
              )

              let hostingView = NSHostingView(rootView: contentView)
              window.contentView = hostingView
              controller.showWindow(nil)
              hasWindow = true
            }
          }
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
