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
    (color.color ?? .accentColor).contrastingLabel
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
