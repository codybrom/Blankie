//
//  SoundGraphicEQ.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import SwiftUI

/// A named curve for the equalizer, as one gain in dB per `SoundEqualizer` band.
enum GraphicEQPreset: String, CaseIterable, Identifiable {
  case flat
  case increaseBass
  case reduceBass
  case increaseTreble
  case reduceTreble
  case deep
  case smallSpeakers
  case nextRoom
  case oldRadio

  var id: String { rawValue }

  var name: String {
    switch self {
    case .flat:
      String(localized: "Flat", comment: "Equalizer preset that leaves the sound unchanged.")
    case .increaseBass: String(localized: "Increase Bass", comment: "Equalizer preset name.")
    case .reduceBass: String(localized: "Reduce Bass", comment: "Equalizer preset name.")
    case .increaseTreble: String(localized: "Increase Treble", comment: "Equalizer preset name.")
    case .reduceTreble: String(localized: "Reduce Treble", comment: "Equalizer preset name.")
    case .deep:
      String(
        localized: "Deep",
        comment: "Equalizer preset that makes a sound fuller and softens its high end.")
    case .smallSpeakers: String(localized: "Small Speakers", comment: "Equalizer preset name.")
    case .nextRoom:
      String(
        localized: "Next Room",
        comment: "Equalizer preset that muffles a sound as if heard through a wall.")
    case .oldRadio:
      String(
        localized: "Old Radio",
        comment: "Equalizer preset that makes a sound thin, like a small old radio.")
    }
  }

  var gains: [Float] {
    switch self {
    case .flat: [0, 0, 0, 0, 0, 0, 0]
    case .increaseBass: [15, 12, 6, 0, 0, 0, 0]
    case .reduceBass: [-18, -14, -7, 0, 0, 0, 0]
    case .increaseTreble: [0, 0, 0, 0, 6, 12, 15]
    case .reduceTreble: [0, 0, 0, 0, -7, -14, -18]
    case .deep: [10, 8, 5, 2, -3, -7, -10]
    case .smallSpeakers: [12, 9, 4, 0, -4, -8, -10]
    case .nextRoom: [3, 2, 0, -7, -14, -18, -18]
    case .oldRadio: [-18, -15, -5, 3, 5, -9, -18]
    }
  }

  /// The preset whose curve is exactly `gains`, if any.
  static func matching(_ gains: [Float]) -> GraphicEQPreset? {
    allCases.first { $0.gains == gains }
  }

  /// The matching preset's name, or Custom for a hand-set curve.
  static func name(for gains: [Float]) -> String {
    matching(gains)?.name
      ?? String(
        localized: "equalizer.preset.custom", defaultValue: "Custom",
        comment: "Shown in place of an equalizer preset name after the bands are moved by hand.")
  }
}

/// A graphic equalizer for one sound. A pop-up button picks a preset, and
/// picking one moves the seven band sliders so the bank shows what the preset
/// does. Moving a slider by hand switches it to Custom. A live spectrum behind
/// the sliders shows the sound band by band. Changes save as they're made.
struct SoundGraphicEQ: View {
  let sound: Sound
  @Binding var isPreviewing: Bool

  @State private var gains: [Float] = SoundEqualizer.flat
  @State private var preset: GraphicEQPreset? = .flat
  @State private var dragStartGains: [Int: Float] = [:]
  @State private var meter = SoundSpectrumMeter(centers: SoundEqualizer.frequencies)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let sliderLength: CGFloat = 200
  private static let handleHeight: CGFloat = 7
  private static let range = SoundEqualizer.rangeDB
  /// How far one VoiceOver swipe or arrow key press moves a band, in dB.
  private static let keyStep: Float = 3
  private static let labels = ["60", "150", "400", "1K", "2.4K", "6K", "15K"]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        previewButton
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
      gains = sound.equalizerGains
      preset = GraphicEQPreset.matching(gains)
    }
    .onDisappear { meter.stop() }
    .onChange(of: reduceMotion) { _, reduceMotion in
      if reduceMotion {
        meter.stop()
      } else {
        meter.start(for: sound)
      }
    }
    .onChange(of: preset) { _, preset in
      guard let preset, preset.gains != gains else { return }
      withAnimation(.snappy) { gains = preset.gains }
      sound.setEqualizer(gains: gains)
    }
    .sensoryFeedback(.selection, trigger: gains.map { Int($0.rounded()) })
  }

  /// Plays the sound so the curve can be heard. Styled like the preset menu
  /// across from it.
  private var previewButton: some View {
    Button {
      isPreviewing.toggle()
    } label: {
      Label(
        isPreviewing ? "Stop" : "Play",
        systemImage: isPreviewing ? "stop.fill" : "play.fill"
      )
      .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .fixedSize()
    .accessibilityLabel(isPreviewing ? Text("Stop Preview") : Text("Play Preview"))
  }

  /// A standard pop-up button. It names the current preset, or Custom after a
  /// hand edit, and opens the full list with a checkmark.
  private var presetMenu: some View {
    Menu {
      Picker(selection: $preset) {
        ForEach(GraphicEQPreset.allCases) { item in
          Text(item.name).tag(Optional(item))
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: 6) {
        Text(GraphicEQPreset.name(for: gains))
        Image(systemName: "chevron.up.chevron.down")
          .imageScale(.small)
          .accessibilityHidden(true)
      }
    }
    .menuIndicator(.hidden)
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .fixedSize()
    .accessibilityLabel(Text("Equalizer"))
    .accessibilityValue(Text(GraphicEQPreset.name(for: gains)))
  }

  private func band(_ index: Int) -> some View {
    VStack(spacing: 8) {
      fader(index)

      Text(verbatim: Self.labels[index])
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity)
  }

  /// A slim handle riding on the band's meter column, which doubles as the
  /// track. The system slider's handle can't be restyled, so this is drawn by
  /// hand, and VoiceOver gets a standard slider in its place.
  private func fader(_ index: Int) -> some View {
    let travel = Self.sliderLength - Self.handleHeight
    let fraction = CGFloat((gains[index] + Self.range) / (2 * Self.range))
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
          let moved = -Float(value.translation.height / travel) * 2 * Self.range
          let gain = start + moved
          // Snaps to 0 dB near the middle.
          setGain(abs(gain) < 1.1 ? 0 : gain, at: index)
        }
        .onEnded { _ in dragStartGains[index] = nil }
    )
    .accessibilityRepresentation {
      Slider(
        value: Binding {
          gains[index]
        } set: {
          setGain($0, at: index)
        },
        in: -Self.range...Self.range,
        step: Self.keyStep
      ) {
        Text(
          Measurement(value: Double(SoundEqualizer.frequencies[index]), unit: UnitFrequency.hertz)
            .formatted(.measurement(width: .wide, usage: .asProvided)))
      }
      .accessibilityValue(Text(verbatim: Self.decibelText(gains[index])))
    }
    #if os(macOS)
      // Joins keyboard focus only with Keyboard navigation on, like a native slider.
      .focusable(interactions: .activate)
      .onMoveCommand { direction in
        switch direction {
        case .up: setGain(gains[index] + Self.keyStep, at: index)
        case .down: setGain(gains[index] - Self.keyStep, at: index)
        default: break
        }
      }
    #endif
  }

  private static func decibelText(_ gain: Float) -> String {
    let number = gain.formatted(
      .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
    return "\(number) dB"
  }

  /// Clamps to the band range. A hand edit leaves the preset.
  private func setGain(_ newValue: Float, at index: Int) {
    let clamped = max(-Self.range, min(Self.range, newValue))
    guard clamped != gains[index] else { return }
    gains[index] = clamped
    preset = GraphicEQPreset.matching(gains)
    sound.setEqualizer(gains: gains)
  }
}

/// The equalizer for one sound, presented from the sound editor.
struct SoundEqualizerSheet: View {
  let sound: Sound
  @Binding var isPreviewing: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      SoundGraphicEQ(sound: sound, isPreviewing: $isPreviewing)
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle(Text("Equalizer"))
        #if !os(macOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    #if os(macOS)
      .frame(width: 420, height: 370)
    #else
      .presentationDetents([.height(385)])
      // A sheet this short is see-through glass by default, which fights the meters.
      .presentationBackground(.thickMaterial)
    #endif
  }
}

#if DEBUG
  /// Preview stand-in for the sound editor: pick a built-in sound and play it.
  private struct EqualizerPreview: View {
    @State private var selected: Sound?
    @State private var isPreviewing = false

    private var sounds: [Sound] {
      AudioManager.shared.sounds.filter { !$0.isCustom }
    }

    var body: some View {
      VStack(spacing: 20) {
        Picker(selection: $selected) {
          ForEach(sounds) { sound in
            Text(verbatim: sound.title).tag(Optional(sound))
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.menu)

        if let selected {
          SoundGraphicEQ(sound: selected, isPreviewing: $isPreviewing)
            .padding()
            .id(selected.id)
        }
      }
      .padding()
      .onAppear {
        selected = sounds.first { $0.fileName == "rain" } ?? sounds.first
      }
      .onChange(of: isPreviewing) { _, previewing in
        guard let selected else { return }
        if previewing {
          AudioManager.shared.enterPreviewMode(for: selected)
        } else {
          AudioManager.shared.exitPreviewMode(resuming: false)
        }
      }
      .onChange(of: selected) { _, new in
        guard isPreviewing, let new else { return }
        AudioManager.shared.exitPreviewMode(resuming: false)
        AudioManager.shared.enterPreviewMode(for: new)
      }
    }
  }

  #Preview("Graphic EQ") {
    EqualizerPreview()
      .preferredColorScheme(.dark)
  }

  #Preview("Equalizer Sheet") {
    if let rain = AudioManager.shared.sounds.first(where: { $0.fileName == "rain" }) {
      SoundEqualizerSheet(sound: rain, isPreviewing: .constant(false))
        .preferredColorScheme(.dark)
    }
  }
#endif
