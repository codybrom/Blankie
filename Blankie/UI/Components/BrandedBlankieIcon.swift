//
//  BrandedBlankieIcon.swift
//  Blankie
//
//  Branded Blankie symbol icon with gradient styling
//

import SwiftUI

/// A branded Blankie symbol icon with gradient styling matching the onboarding design.
/// Used as a fallback placeholder for preset artwork throughout the app.
struct BrandedBlankieIcon: View {
  let size: CGFloat
  var color: Color? = nil
  @StateObject private var globalSettings = GlobalSettings.shared

  var body: some View {
    Image("blankie.symbol")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: size, height: size)
      .symbolRenderingMode(.palette)
      .foregroundStyle(
        LinearGradient(
          colors: [
            color ?? globalSettings.customAccentColor ?? .accentColor,
            (color ?? globalSettings.customAccentColor ?? .accentColor).opacity(0.7),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .accessibilityHidden(true)
  }
}

#Preview {
  VStack(spacing: 20) {
    BrandedBlankieIcon(size: 18)
    BrandedBlankieIcon(size: 60)
    BrandedBlankieIcon(size: 120)
  }
  .padding()
}
