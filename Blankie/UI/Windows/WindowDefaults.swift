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

    static func defaultContentView(
      showingShortcuts: Binding<Bool>
    ) -> some View {
      MacRootView(showingShortcuts: showingShortcuts)
    }
  }
#endif
