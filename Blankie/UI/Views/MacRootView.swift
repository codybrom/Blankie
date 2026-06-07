//
//  MacRootView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

#if os(macOS)
  import SwiftUI

  /// macOS root: the iPad Library sidebar paired with the mixer in a split view,
  /// replacing the old toolbar preset picker and hamburger menu.
  struct MacRootView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @Binding var showingShortcuts: Bool

    var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarContentView()
          .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 450)
      } detail: {
        ContentView(showingShortcuts: $showingShortcuts)
      }
      // The window's floor follows the sidebar: collapsed it can shrink to a
      // compact mixer; open it must hold sidebar + a usable detail pane.
      .frame(
        minWidth: columnVisibility == .detailOnly
          ? WindowDefaults.minWidth : WindowDefaults.minWidthWithSidebar,
        minHeight: WindowDefaults.minHeight)
    }
  }
#endif
