//
//  View+HandCursor.swift
//  Blankie
//
//  Created by Cody Bromley on 6/2/26.
//

import SwiftUI

extension View {
  /// Shows the pointing-hand (link) pointer while hovering this view on macOS via
  /// `.pointerStyle(.link)`. A no-op on other platforms.
  func handCursor() -> some View {
    #if os(macOS)
      pointerStyle(.link)
    #else
      self
    #endif
  }
}
