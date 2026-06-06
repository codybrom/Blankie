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
      .frame(minWidth: WindowDefaults.minWidth, minHeight: WindowDefaults.minHeight)
    }
  }
#endif
