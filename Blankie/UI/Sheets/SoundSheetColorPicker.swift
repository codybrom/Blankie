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

  var currentColor: Color {
    if let selectedColor = selectedColor, let color = selectedColor.color {
      return color
    }
    return globalSettings.customAccentColor ?? .accentColor
  }

  var body: some View {
    NavigationLink(destination: ColorPickerPage(selectedColor: $selectedColor)) {
      HStack {
        Text("Color", comment: "Color picker label")
        Spacer()
        Circle()
          .fill(currentColor)
          .frame(width: 20, height: 20)
      }
    }
  }
}

struct ColorPickerPage: View {
  @Binding var selectedColor: AccentColor?
  @ObservedObject var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss

  private let columns = [
    GridItem(.adaptive(minimum: 44)),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        LazyVGrid(columns: columns, spacing: 16) {
          // Default option - use accent color
          Button(action: {
            selectedColor = nil
            dismiss()
          }) {
            VStack {
              ZStack {
                Circle()
                  .fill(globalSettings.customAccentColor ?? .accentColor)
                  .frame(width: 44, height: 44)

                if selectedColor == nil {
                  Image(systemName: "checkmark")
                    .foregroundColor(.white)
                }
              }

              Text("Theme", comment: "Accent color option")
                .font(.caption)
            }
          }
          .buttonStyle(.plain)

          // Color options
          ForEach(AccentColor.allCases.dropFirst(), id: \.self) { colorOption in
            Button(action: {
              selectedColor = colorOption
              dismiss()
            }) {
              VStack {
                ZStack {
                  Circle()
                    .fill(colorOption.color ?? .accentColor)
                    .frame(width: 44, height: 44)

                  if selectedColor == colorOption {
                    Image(systemName: "checkmark")
                      .foregroundColor(.white)
                  }
                }

                Text(colorOption.name)
                  .font(.caption)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding()
      }
    }
    .navigationTitle("Color")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}
