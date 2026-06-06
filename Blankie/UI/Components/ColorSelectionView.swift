//
//  ColorSelectionView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct ColorSelectionView: View {
  @Binding var selectedColor: AccentColor?
  @ObservedObject private var globalSettings = GlobalSettings.shared

  var textColorForCurrentTheme: Color {
    (globalSettings.customAccentColor ?? .accentColor).contrastingLabel
  }

  func textColorForAccentColor(_ accentColor: AccentColor) -> Color {
    guard let color = accentColor.color else { return .white }
    return color.contrastingLabel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Color")
        .font(.headline)
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        // Default option - styled like PreferencesView
        HStack(spacing: 8) {
          Button(
            action: { selectedColor = nil },
            label: {
              Text("Current Theme")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  selectedColor == nil
                    ? (globalSettings.customAccentColor ?? Color.accentColor)
                    : Color.secondary.opacity(0.2)
                )
                .foregroundColor(
                  selectedColor == nil ? textColorForCurrentTheme : .primary
                )
                .cornerRadius(6)
            }
          )
          .buttonStyle(.plain)
          .accessibilityAddTraits(selectedColor == nil ? .isSelected : [])

          // First row of colors
          ForEach(Array(AccentColor.allCases.filter { $0 != .system }.prefix(5)), id: \.self) {
            accentColor in
            Button(action: {
              selectedColor = accentColor
            }) {
              RoundedRectangle(cornerRadius: 4)
                .fill(accentColor.color ?? Color.accentColor)
                .frame(width: 24, height: 24)
                .overlay {
                  if selectedColor == accentColor {
                    RoundedRectangle(cornerRadius: 4)
                      .strokeBorder(
                        textColorForAccentColor(accentColor),
                        lineWidth: 2
                      )
                      .padding(2)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accentColor.name)
            .accessibilityAddTraits(selectedColor == accentColor ? .isSelected : [])
          }
        }

        // Second row of colors
        HStack(spacing: 8) {
          ForEach(Array(AccentColor.allCases.filter { $0 != .system }.dropFirst(5)), id: \.self) {
            accentColor in
            Button(action: {
              selectedColor = accentColor
            }) {
              RoundedRectangle(cornerRadius: 4)
                .fill(accentColor.color ?? Color.accentColor)
                .frame(width: 24, height: 24)
                .overlay {
                  if selectedColor == accentColor {
                    RoundedRectangle(cornerRadius: 4)
                      .strokeBorder(
                        textColorForAccentColor(accentColor),
                        lineWidth: 2
                      )
                      .padding(2)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accentColor.name)
            .accessibilityAddTraits(selectedColor == accentColor ? .isSelected : [])
          }
        }
      }
      .padding(.vertical, 4)
      // Group the swatches so VoiceOver announces a "Color" group
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text("Color"))
    }
  }
}
