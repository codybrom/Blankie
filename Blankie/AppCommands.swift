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

    var body: some Commands {
      CommandGroup(replacing: .appInfo) {
        Button {
          showingAbout = true
          appState.isAboutViewPresented = true
        } label: {
          Text("About Blankie", comment: "About menu command")
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
                presetName: .constant(""),
                showingSettings: .constant(false)
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
      }

      CommandGroup(after: .toolbar) {
        Button(appState.hideInactiveSounds ? "Show All Sounds" : "Hide Inactive Sounds") {
          withAnimation {
            appState.hideInactiveSounds.toggle()
            UserDefaults.standard.set(appState.hideInactiveSounds, forKey: "hideInactiveSounds")
          }
        }
        .keyboardShortcut("h", modifiers: [.control, .command])

        Button(GlobalSettings.shared.showSoundNames ? "Hide Sound Names" : "Show Sound Names") {
          withAnimation {
            GlobalSettings.shared.setShowSoundNames(!GlobalSettings.shared.showSoundNames)
          }
        }
        .keyboardShortcut("n", modifiers: [.control, .command])

        Divider()

        Menu("Icon Size") {
          ForEach(IconSize.allCases, id: \.self) { size in
            Button(size.label) {
              withAnimation {
                GlobalSettings.shared.setIconSize(size)
              }
            }
            .keyboardShortcut(
              size == .small ? "1" : size == .medium ? "2" : "3",
              modifiers: [.control, .command]
            )
            .disabled(GlobalSettings.shared.iconSize == size)
          }
        }
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
