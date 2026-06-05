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
    static let minWidth: CGFloat = 428
    static let minHeight: CGFloat = 275
    static let defaultWidth: CGFloat = 950
    static let defaultHeight: CGFloat = 540

    static let defaultFrame = NSRect(
      x: 0,
      y: 0,
      width: defaultWidth,
      height: defaultHeight
    )

    static let styleMask: NSWindow.StyleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
    ]

    static func configureWindow(_ window: NSWindow) {
      window.title = title
      window.toolbarStyle = .unified
      window.minSize = NSSize(width: minWidth, height: minHeight)
      window.isExcludedFromWindowsMenu = true
      window.tabbingMode = .disallowed

      // Get saved frame
      let savedFrame = WindowObserver.shared.getLastWindowFrame()

      // Set window frame with saved dimensions
      window.setFrame(savedFrame, display: true)

      // Center window if no saved position
      if !UserDefaults.standard.bool(forKey: "HasSavedWindowPosition") {
        window.center()
        UserDefaults.standard.set(true, forKey: "HasSavedWindowPosition")
      }
    }

    static func defaultContentView(
      showingAbout: Binding<Bool>,
      showingShortcuts: Binding<Bool>
    ) -> some View {
      MacRootView(showingAbout: showingAbout, showingShortcuts: showingShortcuts)
    }
  }
#endif
