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
    @Binding var hasWindow: Bool
    @StateObject private var appState = AppState.shared
    @StateObject private var audioManager = AudioManager.shared

    var body: some Commands {
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
                showingShortcuts: .constant(false),
                showingNewPresetPopover: .constant(false),
                presetName: .constant("")
              )

              let hostingView = NSHostingView(rootView: contentView)
              window.contentView = hostingView
              controller.showWindow(nil)
              hasWindow = true
            }
          }
        }
        .disabled(hasWindow)
        .keyboardShortcut("n", modifiers: .command)

        Divider()

        Button("Import") {
          appState.showingImport = true
        }
        .keyboardShortcut("i", modifiers: .command)
      }

      // Add Help menu command
      CommandGroup(replacing: .help) {
        Button("Blankie Help") {
          if let url = URL(string: "https://blankie.rest/faq") {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }
  }
#endif
