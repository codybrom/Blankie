//
//  SoundGraphicEQ.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import SwiftUI

/// SPIKE: a named curve for the graphic EQ, as seven band gains in dB (60 Hz to
/// 15 kHz). Names and curves are placeholders.
enum GraphicEQPreset: String, CaseIterable, Identifiable {
  case flat
  case bassBooster
  case bassReducer
  case trebleBooster
  case trebleReducer
  case smallSpeakers
  case nextRoom
  case oldRadio

  var id: String { rawValue }

  var name: String {
    switch self {
    case .flat: "Flat"
    case .bassBooster: "Bass Booster"
    case .bassReducer: "Bass Reducer"
    case .trebleBooster: "Treble Booster"
    case .trebleReducer: "Treble Reducer"
    case .smallSpeakers: "Small Speakers"
    case .nextRoom: "Next Room"
    case .oldRadio: "Old Radio"
    }
  }

  var gains: [Double] {
    switch self {
    case .flat: [0, 0, 0, 0, 0, 0, 0]
    case .bassBooster: [15, 12, 6, 0, 0, 0, 0]
    case .bassReducer: [-18, -14, -7, 0, 0, 0, 0]
    case .trebleBooster: [0, 0, 0, 0, 6, 12, 15]
    case .trebleReducer: [0, 0, 0, 0, -7, -14, -18]
    case .smallSpeakers: [12, 9, 4, 0, -4, -8, -10]
    case .nextRoom: [3, 2, 0, -7, -14, -18, -18]
    case .oldRadio: [-18, -15, -5, 3, 5, -9, -18]
    }
  }
}

/// SPIKE: an old-school graphic equalizer for one sound. A pop-up button picks a
/// preset, and picking one moves the seven band sliders so the bank shows what
/// the preset does. Moving a slider by hand switches it to Custom. A live
/// spectrum behind the sliders shows the sound band by band. Throwaway: no
/// persistence.
struct SoundGraphicEQ: View {
  let sound: Sound

  @State private var gains: [Double] = GraphicEQPreset.flat.gains
  @State private var preset: GraphicEQPreset? = .flat
  @State private var dragStartGains: [Int: Double] = [:]
  @State private var meter = SoundSpectrumMeter(centers: SoundPlayer.graphicEQFrequencies)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let sliderLength: CGFloat = 200
  private static let handleHeight: CGFloat = 7
  private static let range = Double(SoundPlayer.graphicEQRangeDB)
  private static let labels = ["60", "150", "400", "1K", "2.4K", "6K", "15K"]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(verbatim: "Equalizer")
          .font(.headline)
        Spacer()
        presetMenu
      }

      HStack(alignment: .top, spacing: 0) {
        ForEach(gains.indices, id: \.self) { index in
          band(index)
        }
      }
      // The 0 dB line. A slider sitting on it is leaving that band alone.
      .background(alignment: .top) {
        Rectangle()
          .fill(.secondary.opacity(0.5))
          .frame(height: 1)
          .offset(y: Self.sliderLength / 2)
      }
    }
    .onAppear {
      if !reduceMotion { meter.start(for: sound) }
      let current = sound.graphicEQGains.map(Double.init)
      guard current.count == gains.count else { return }
      gains = current
      preset = GraphicEQPreset.allCases.first { $0.gains == current }
    }
    .onDisappear { meter.stop() }
    .onChange(of: preset) { _, preset in
      guard let preset else { return }
      withAnimation(.snappy) { gains = preset.gains }
      apply()
    }
    .sensoryFeedback(.selection, trigger: gains.map { Int($0.rounded()) })
  }

  /// A standard pop-up button. It names the current preset, or Custom after a
  /// hand edit, and opens the full list with a checkmark.
  private var presetMenu: some View {
    Menu {
      Picker(selection: $preset) {
        ForEach(GraphicEQPreset.allCases) { item in
          Text(verbatim: item.name).tag(Optional(item))
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: 6) {
        Text(verbatim: preset?.name ?? "Custom")
        Image(systemName: "chevron.up.chevron.down")
          .imageScale(.small)
      }
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
  }

  private func band(_ index: Int) -> some View {
    VStack(spacing: 8) {
      fader(index)

      Text(verbatim: Self.labels[index])
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  /// A slim handle riding on the band's meter column, which doubles as the
  /// track. The system slider's handle can't be restyled, so this is drawn by
  /// hand, and VoiceOver gets a standard slider in its place.
  private func fader(_ index: Int) -> some View {
    let travel = Self.sliderLength - Self.handleHeight
    let fraction = (gains[index] + Self.range) / (2 * Self.range)
    return SpectrumColumn(
      level: reduceMotion ? 0 : meter.levels[index], height: Self.sliderLength
    )
    .overlay(alignment: .top) {
      Capsule()
        .fill(.white)
        .frame(width: 34, height: Self.handleHeight)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .offset(y: (1 - fraction) * travel)
    }
    .frame(maxWidth: .infinity)
    .contentShape(.rect)
    .gesture(
      // Relative, so touching the column never makes the handle jump.
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          let start = dragStartGains[index] ?? gains[index]
          dragStartGains[index] = start
          let moved = -Double(value.translation.height / travel) * 2 * Self.range
          setGain(max(-Self.range, min(Self.range, start + moved)), at: index)
        }
        .onEnded { _ in dragStartGains[index] = nil }
    )
    .accessibilityRepresentation {
      Slider(
        value: Binding { gains[index] } set: { setGain($0, at: index) },
        in: -Self.range...Self.range
      ) {
        Text(verbatim: "\(Self.labels[index]) hertz")
      }
    }
  }

  /// Snaps to 0 dB near the middle, and a hand edit leaves the preset.
  private func setGain(_ newValue: Double, at index: Int) {
    let snapped = abs(newValue) < 1.1 ? 0 : newValue
    guard snapped != gains[index] else { return }
    gains[index] = snapped
    if let current = preset, current.gains != gains { preset = nil }
    apply()
  }

  private func apply() {
    sound.setGraphicEQ(gains: gains.map(Float.init))
  }
}

#Preview("Graphic EQ") {
  SoundPrototypeHarness { sound in
    SoundGraphicEQ(sound: sound)
      .padding()
      .background(.fill.tertiary, in: .rect(cornerRadius: 26, style: .continuous))
  }
  .preferredColorScheme(.dark)
}
