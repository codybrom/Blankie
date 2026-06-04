//
//  SoundSheetForm+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import SwiftUI

// MARK: - Color Helpers
extension SoundSheetForm {
  var textColorForCurrentTheme: Color {
    let color = globalSettings.customAccentColor ?? .accentColor
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }

  func textColorForAccentColor(_ accentColor: AccentColor) -> Color {
    guard let color = accentColor.color else { return .white }
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }
}

// MARK: - Volume Helpers
extension SoundSheetForm {
  var volumePercentageText: String {
    let delta = Double(volumeAdjustment) - 1.0
    return delta.formatted(
      .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
  }
}

// MARK: - Preview Helpers
extension SoundSheetForm {
  func togglePreview() {
    isPreviewing.toggle()
  }

  func startPreview() {
    isPreviewing = true
  }

  func stopPreview() {
    isPreviewing = false
  }
}

