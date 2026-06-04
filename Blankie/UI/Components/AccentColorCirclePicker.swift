//
//  AccentColorCirclePicker.swift
//  Blankie
//
//  Created by Cody Bromley on 5/25/26.
//

#if os(macOS)
  import SwiftUI

  /// Circle-swatch accent color picker for macOS
  ///
  /// Binds to an optional `Color`. When `allowSystem` is true the first swatch
  /// represents "System" — selecting it clears the binding to `nil`. The
  /// per-preset editor passes `allowSystem: false` because its separate
  /// "Accent Color" toggle already handles the off state.
  struct AccentColorCirclePicker: View {
    @Binding var selectedColor: Color?
    var allowSystem: Bool = true

    private var options: [AccentColor] {
      allowSystem ? AccentColor.allCases : AccentColor.allCases.filter { $0 != .system }
    }

    private let columns = [GridItem(.adaptive(minimum: 36), spacing: 10)]

    var body: some View {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
        ForEach(options, id: \.self) { option in
          swatch(for: option)
        }
      }
      .padding(.vertical, 4)
    }

    private func isSelected(_ option: AccentColor) -> Bool {
      if option == .system { return selectedColor == nil }
      return option.color == selectedColor
    }

    @ViewBuilder
    private func swatch(for option: AccentColor) -> some View {
      let selected = isSelected(option)
      Button {
        selectedColor = option.color
      } label: {
        ZStack {
          Circle()
            .fill(option.color ?? Color(NSColor.tertiaryLabelColor))
            .frame(width: 26, height: 26)
            .overlay(
              // Give the empty "System" swatch a faint outline so it reads as a
              // real, tappable choice rather than a blank gap.
              Circle().strokeBorder(
                .secondary.opacity(option == .system ? 0.4 : 0), lineWidth: 1)
            )

          if selected {
            Circle()
              .strokeBorder(.primary, lineWidth: 2)
              .frame(width: 34, height: 34)
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(option == .system ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
          }
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(option.name)
      .accessibilityLabel(option.name)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  #Preview {
    AccentColorCirclePicker(selectedColor: .constant(.orange))
      .padding()
      .frame(width: 320)
  }
#endif
