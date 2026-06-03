//
//  ColorSquare.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

struct ColorSquare: View {
  let color: AccentColor
  let isSelected: Bool
  @ObservedObject private var globalSettings = GlobalSettings.shared

  var textColorForAccent: Color {
    #if os(macOS)
      if let nsColor = NSColor(color.color ?? .accentColor).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #elseif os(iOS) || os(visionOS)
      // Convert SwiftUI Color to UIColor
      let uiColor = UIColor(color.color ?? .accentColor)

      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0

      uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      let brightness = (0.299 * red) + (0.587 * green) + (0.114 * blue)
      return brightness > 0.5 ? .black : .white
    #else
      return .white
    #endif
  }

  var body: some View {
    Button(action: {
      globalSettings.setAccentColor(color.color)
    }) {
      RoundedRectangle(cornerRadius: 4)
        .fill(color.color ?? Color.accentColor)
        .frame(width: 24, height: 24)
        .overlay {
          if isSelected {
            RoundedRectangle(cornerRadius: 4)
              .strokeBorder(textColorForAccent, lineWidth: 2)
              .padding(2)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(color.name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
