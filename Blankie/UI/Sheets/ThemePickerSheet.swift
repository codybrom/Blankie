//
//  ThemePickerSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct ThemePickerSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var globalSettings = GlobalSettings.shared

    var body: some View {
      NavigationStack {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
              .font(.headline)

            HStack {
              Spacer()
              HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                  Button(action: {
                    globalSettings.setAppearance(mode)
                  }) {
                    HStack(spacing: 4) {
                      Image(systemName: mode.icon)
                      Text(mode.localizedName)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                      globalSettings.appearance == mode
                        ? (globalSettings.customAccentColor ?? .accentColor)
                        : Color.secondary.opacity(0.2)
                    )
                    .foregroundColor(
                      globalSettings.appearance == mode ? .white : .primary
                    )
                    .cornerRadius(8)
                  }
                  .buttonStyle(.plain)
                }
              }
              Spacer()
            }
          }

          VStack(alignment: .leading, spacing: 12) {
            Text("Accent Color")
              .font(.headline)

            SpectrumColorPicker(selectedColor: $globalSettings.customAccentColor)
              .padding(.vertical, 8)
              .onChange(of: globalSettings.customAccentColor) { _, newColor in
                globalSettings.setAccentColor(newColor)
              }
          }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            let needsReset =
              globalSettings.appearance != .system || globalSettings.customAccentColor != nil
            if needsReset {
              Button("Reset") {
                globalSettings.setAppearance(.system)
                globalSettings.setAccentColor(nil)
              }
              .tint(Color.primary)
            }
          }

          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              isPresented = false
            }
            .tint(Color.primary)
          }
        }
      }
      .presentationDetents([.fraction(0.45)])
    }
  }
#endif
