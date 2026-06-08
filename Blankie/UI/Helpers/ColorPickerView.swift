//
//  ColorPickerView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

/// Accent color picker shown from the macOS bottom bar's palette popover
struct ColorPickerView: View {
  @ObservedObject var globalSettings = GlobalSettings.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Accent Color")
        .font(.headline)
        .padding(.bottom, 4)

      ForEach(AccentColor.allCases.filter { $0 != .system }, id: \.self) { color in
        Button(action: {
          globalSettings.setAccentColor(color.color)
        }) {
          HStack {
            Circle()
              .fill(color.color ?? .accentColor)
              .frame(width: 16, height: 16)
              .accessibilityHidden(true)

            Text(color.name)
              .foregroundColor(.primary)

            Spacer()

            if color.color == globalSettings.customAccentColor {
              Image(systemName: "checkmark")
                .foregroundColor(.blue)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityAddTraits(
          color.color == globalSettings.customAccentColor ? .isSelected : []
        )
      }
    }
    .frame(width: 200)
  }
}
