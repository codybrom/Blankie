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
            globalSettings.customAccentColor ?? .accentColor,
            (globalSettings.customAccentColor ?? .accentColor).opacity(0.7),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
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
