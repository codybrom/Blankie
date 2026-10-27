//
//  SpectrumColorPicker.swift
//  Blankie
//
//  Created by Cody Bromley on 1/22/25.
//

import SwiftUI

struct SpectrumColorPicker: View {
  @Binding var selectedColor: Color?
  @State private var sliderValue: Double = 0
  @State private var currentColorName = ""
  @State private var showingChip = false
  @State private var isDragging = false

  private let globalSettings = GlobalSettings.shared
  @Environment(\.colorScheme) private var colorScheme

  // Available colors in custom spectrum order
  private let spectrumColors: [AccentColor] = [
    .green, .mint, .teal, .cyan, .blue,
    .indigo, .purple, .pink, .red, .orange,
    .yellow, .brown,
  ]

  private func updateSliderValue() {
    if let selectedColor = selectedColor,
      let accentColor = spectrumColors.firstIndex(where: { $0.color == selectedColor })
    {
      sliderValue = Double(accentColor)
    } else {
      sliderValue = 0
    }
    currentColorName = currentColor.name
  }

  private var currentColor: AccentColor {
    let index = Int(round(sliderValue))
    let clampedIndex = max(0, min(index, spectrumColors.count - 1))
    return spectrumColors[clampedIndex]
  }

  private var textColor: Color {
    // For lighter colors use black text, for darker colors use white
    switch currentColor {
    case .yellow, .mint, .cyan, .orange:
      return .black
    default:
      return .white
    }
  }

  private var borderColor: Color {
    (currentColor.color ?? .blue).opacity(0.6)
  }

  @ViewBuilder
  private func gradientTrack(geometry: GeometryProxy) -> some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    ZStack {
      // Base glass material (slightly more opaque than ultra-thin)
      shape
        .fill(.thinMaterial)

      // Spectrum tint over the glass (stronger)
      shape
        .fill(
          LinearGradient(
            gradient: Gradient(
              colors: {
                var colors = spectrumColors.compactMap { $0.color }
                if let first = colors.first { colors.insert(first, at: 0) }
                if let last = colors.last { colors.append(last) }
                return colors
              }()),
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .opacity(0.75)

      // Soft inner highlight on top edge
      shape
        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
        .blur(radius: 1)
        .offset(y: -1)
        .mask(shape)
        .opacity(0.6)

      // Subtle border for definition
      shape
        .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.75)

      // Glow ring when interacting
      shape
        .strokeBorder((currentColor.color ?? .blue).opacity(isDragging ? 0.7 : 0), lineWidth: 1)
        .blur(radius: 6)
        .opacity(isDragging ? 1 : 0)
    }
    .frame(width: geometry.size.width + 28, height: 32)
    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    // Base shadow for depth
    .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
    // Color glow while dragging
    .shadow(
      color: (currentColor.color ?? .blue).opacity(isDragging ? 0.55 : 0),
      radius: isDragging ? 18 : 0, x: 0, y: 0
    )
    .animation(.easeInOut(duration: 0.18), value: isDragging)
  }

  @ViewBuilder
  private func colorChip(geometry: GeometryProxy) -> some View {
    if showingChip {
      let sliderProgress = sliderValue / Double(spectrumColors.count - 1)
      let xPosition = 20 + (sliderProgress * (geometry.size.width - 40))

      Text(currentColorName)
        .font(.system(.footnote, design: .rounded))
        .fontWeight(.semibold)
        .foregroundStyle(textColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
          Capsule()
            .fill(currentColor.color ?? .blue)
            .overlay(
              Capsule()
                .strokeBorder(borderColor, lineWidth: 1.5)
            )
        )
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        .position(x: xPosition, y: -25)
        .transition(.opacity)
    }
  }

  // Native Slider with a tick per spectrum color.
  @ViewBuilder
  private var baseSlider: some View {
    let onEditing: (Bool) -> Void = { editing in
      if editing {
        if !isDragging {
          isDragging = true
          currentColorName = currentColor.name
          withAnimation(.easeIn(duration: 0.2)) {
            showingChip = true
          }
        }
      } else {
        isDragging = false
        selectedColor = currentColor.color
        withAnimation(.easeOut(duration: 0.2)) {
          showingChip = false
        }

        #if os(iOS)
          let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
          impactFeedback.prepare()
          impactFeedback.impactOccurred()
        #endif
      }
    }

    Slider(
      value: $sliderValue,
      in: 0...Double(spectrumColors.count - 1),
      label: {
        Text("Accent Color")
      },
      ticks: {
        SliderTickContentForEach(
          stride(from: 0.0, through: 11.0, by: 1.0).map { $0 },
          id: \.self
        ) { value in
          SliderTick(value)
        }
      },
      onEditingChanged: onEditing
    )
  }

  @ViewBuilder
  private var slider: some View {
    baseSlider
      .onChange(of: sliderValue) { _, newValue in
        handleSliderValueChange(newValue)
      }
      .tint(.clear)
      #if os(macOS)
        // macOS renders Slider labels inline, over the gradient track. The form
        // supplies its own heading, so the label stays VoiceOver-only.
        .labelsHidden()
      #endif
      .frame(height: 44)
      .accessibilityValue(Text(currentColor.name))
  }

  @ViewBuilder
  private var trackOverlay: some View {
    GeometryReader { geometry in
      ZStack {
        gradientTrack(geometry: geometry)
        colorChip(geometry: geometry)
      }
      .frame(height: 40)
    }
    .frame(height: 40)
  }

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        GeometryReader { geometry in
          ZStack {
            gradientTrack(geometry: geometry)

            colorChip(geometry: geometry)

          }
          .frame(height: 4)
        }
        .frame(height: 4)
        .accessibilityHidden(true)

        slider
      }
      .frame(height: 44)
      .padding(.horizontal, 20)  // Match padding with other form elements
    }
    .frame(height: 44)
    .onAppear {
      updateSliderValue()
    }
    // Two-way with the slider's onChange (intentional): outside color changes move
    // the slider unless a drag is in progress.
    .onChange(of: selectedColor) { _, _ in
      if !showingChip {
        updateSliderValue()
      }
    }
  }

  private func handleSliderValueChange(_ newValue: Double) {
    // Snap to discrete values
    let rounded = round(newValue)
    if abs(newValue - rounded) < 0.01 {
      sliderValue = rounded
    }

    currentColorName = currentColor.name

    if isDragging {
      selectedColor = currentColor.color

      #if os(iOS)
        // Light haptic on snap
        if abs(newValue - rounded) < 0.01 {
          let impactFeedback = UIImpactFeedbackGenerator(style: .light)
          impactFeedback.prepare()
          impactFeedback.impactOccurred()
        }
      #endif
    }
  }
}

#Preview("Spectrum Color Picker") {
  VStack(spacing: 30) {
    Text("Accent Color Picker")
      .font(.title2)
      .fontWeight(.bold)

    SpectrumColorPicker(selectedColor: .constant(.blue))
      .padding(.horizontal)

    SpectrumColorPicker(selectedColor: .constant(.purple))
      .padding(.horizontal)

    SpectrumColorPicker(selectedColor: .constant(.green))
      .padding(.horizontal)

    SpectrumColorPicker(selectedColor: .constant(nil))
      .padding(.horizontal)

    Spacer()
  }
  .padding()
  #if os(macOS)
    .background(Color(nsColor: .windowBackgroundColor))
  #else
    .background(Color(.systemGroupedBackground))
  #endif
}
