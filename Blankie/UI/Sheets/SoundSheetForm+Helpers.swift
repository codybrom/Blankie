//
//  SoundSheetForm+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import SwiftUI

// MARK: - Color Helpers
extension CleanSoundSheetForm {
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
extension CleanSoundSheetForm {
  var volumePercentageText: String {
    let delta = Double(volumeAdjustment) - 1.0
    return delta.formatted(
      .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
  }
}

// MARK: - Preview Helpers
extension CleanSoundSheetForm {
  func togglePreview() {
    debugLog("🎵 CleanSoundSheetForm: togglePreview called, current isPreviewing: \(isPreviewing)")
    isPreviewing.toggle()
  }

  func startPreview() {
    debugLog("🎵 CleanSoundSheetForm: startPreview called")
    isPreviewing = true
  }

  func stopPreview() {
    debugLog("🎵 CleanSoundSheetForm: stopPreview called")
    isPreviewing = false
  }

  func updatePreviewVolume() {
    debugLog("🎵 CleanSoundSheetForm: updatePreviewVolume called")
    // Volume updates will be handled by onChange modifiers
  }
}

