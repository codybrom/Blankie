//
//  MacRootView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

#if os(macOS)
  import SwiftUI

  /// macOS root: the iPad Library sidebar paired with the mixer in a split view.
  struct MacRootView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @Binding var showingShortcuts: Bool
    @ObservedObject private var appState = AppState.shared
    /// How the sidebar stood before a Kaleidoscope took the whole screen.
    @State private var visibilityBeforeFullScreen: NavigationSplitViewVisibility?

    var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarContentView()
          .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 450)
      } detail: {
        ContentView(showingShortcuts: $showingShortcuts)
      }
      .unsavedMixPrompt()
      // A Kaleidoscope filling the screen puts the sidebar away, then brings it back.
      .onChange(of: appState.kaleidoscopeFullScreen) { _, isFullScreen in
        if isFullScreen {
          visibilityBeforeFullScreen = columnVisibility
          columnVisibility = .detailOnly
        } else if let before = visibilityBeforeFullScreen {
          columnVisibility = before
          visibilityBeforeFullScreen = nil
        }
      }
      // The window's floor follows the sidebar: collapsed it can shrink to a
      // compact mixer. Open, it must hold sidebar + a usable detail pane.
      .frame(
        minWidth: columnVisibility == .detailOnly
          ? WindowDefaults.minWidth : WindowDefaults.minWidthWithSidebar,
        minHeight: WindowDefaults.minHeight)
    }
  }
#endif
