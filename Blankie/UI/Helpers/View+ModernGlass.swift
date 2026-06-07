//
//  View+ModernGlass.swift
//  Blankie
//
//  Created by Cody Bromley on 6/5/26.
//

import SwiftUI

// MARK: - Liquid Glass Effect Extension

extension View {
  /// Liquid Glass card backing (every platform's minimum is a 26-era OS).
  func modernGlassEffect(cornerRadius: CGFloat = 12) -> some View {
    glassEffect(
      .regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
  }
}
