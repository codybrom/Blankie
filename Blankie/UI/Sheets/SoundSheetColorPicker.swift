//
//  SoundSheetColorPicker.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

struct ColorPickerRow: View {
  @Binding var selectedColor: AccentColor?
  @ObservedObject var globalSettings = GlobalSettings.shared
  @State private var useCustomTheme = false

  var body: some View {
    VStack(spacing: 12) {
      Toggle("Accent Color", isOn: $useCustomTheme)
        .onChange(of: useCustomTheme) { _, newValue in
          if !newValue {
            selectedColor = nil
          } else if selectedColor == nil {
            // Default to a color if none selected when toggling on
            selectedColor = .blue
          }
        }

      if useCustomTheme {
        SpectrumColorPicker(selectedColor: Binding(
          get: { selectedColor?.color },
          set: { newColor in
            if let newColor = newColor {
              // Find matching AccentColor
              if let match = AccentColor.allCases.first(where: { $0.color == newColor }) {
                selectedColor = match
              }
            }
          }
        ))
        .padding(.bottom, 4)
      }
    }
    .onAppear {
      useCustomTheme = selectedColor != nil
    }
  }
}
