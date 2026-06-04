//
//  View+HandCursor.swift
//  Blankie
//

import SwiftUI

extension View {
  /// Shows the pointing-hand (link) pointer while hovering this view on macOS.
  ///
  /// Wraps the native `.pointerStyle(.link)` (macOS 15+) behind a platform gate
  /// so call sites stay cross-platform — `pointerStyle` doesn't exist on iOS,
  /// where this is a no-op.
  func handCursor() -> some View {
    #if os(macOS)
      pointerStyle(.link)
    #else
      self
    #endif
  }
}
