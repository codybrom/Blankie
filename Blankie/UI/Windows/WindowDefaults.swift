//
//  WindowDefaults.swift
//  Blankie
//
//  Created by Cody Bromley on 1/11/25.
//

#if os(macOS)
  import SwiftUI

  struct WindowDefaults {
    static let title = "Blankie"
    /// Minimum window width with the sidebar collapsed.
    static let minWidth: CGFloat = 435
    /// Minimum window width while the sidebar is showing (sidebar + a usable
    /// detail grid).
    static let minWidthWithSidebar: CGFloat = 750
    static let minHeight: CGFloat = 275
    /// Launch size, sized for the sidebar-open layout.
    static let defaultWidth: CGFloat = 960
    static let defaultHeight: CGFloat = 635

    static let defaultFrame = NSRect(
      x: 0,
      y: 0,
      width: defaultWidth,
      height: defaultHeight
    )

    static func defaultContentView(
      showingShortcuts: Binding<Bool>
    ) -> some View {
      MacRootView(showingShortcuts: showingShortcuts)
    }
  }
#endif
