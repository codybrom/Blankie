//
//  SoundSynthFilter.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import SwiftUI

/// SPIKE: the filter as requested, synth style. A type switch (off, low pass,
/// high pass), a cutoff slider and a resonance slider, applied live to one sound.
/// Rows only, so it drops into a `Form` section. Throwaway: no persistence.
struct SoundSynthFilter: View {
  let sound: Sound
  /// Called when the person changes a control (not when state loads from the sound).
  var onEdit: (() -> Void)?

  @State private var mode: SynthFilterMode = .off
  /// Slider position 0...1, mapped to 20 Hz...20 kHz on a log scale.
  @State private var cutoffPosition: Double = Self.position(forHz: 1_000)
  @State private var resonance: Double = 0

  var body: some View {
    Group {
      Picker(selection: $mode) {
        Text(verbatim: "Off").tag(SynthFilterMode.off)
        Text(verbatim: "Low Pass").tag(SynthFilterMode.lowPass)
        Text(verbatim: "High Pass").tag(SynthFilterMode.highPass)
      } label: {
        Text(verbatim: "Filter")
      }
      .pickerStyle(.segmented)

      row(title: "Cutoff", value: cutoffText) {
        Slider(value: $cutoffPosition, in: 0...1)
      }
      .disabled(mode == .off)

      row(title: "Resonance", value: resonance.formatted(.percent.precision(.fractionLength(0)))) {
        Slider(value: $resonance, in: 0...1)
      }
      .disabled(mode == .off)
    }
    .onAppear {
      mode = sound.synthFilterMode
      cutoffPosition = Self.position(forHz: Double(sound.synthFilterCutoff))
      resonance = Double(sound.synthFilterResonance)
    }
    .onChange(of: mode) { apply() }
    .onChange(of: cutoffPosition) { apply() }
    .onChange(of: resonance) { apply() }
  }

  private func row(title: String, value: String, @ViewBuilder slider: () -> some View)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(verbatim: title)
        Spacer()
        Text(verbatim: value)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      slider()
    }
  }

  private var cutoffHz: Double { 20 * pow(1_000, cutoffPosition) }

  private var cutoffText: String {
    cutoffHz.rounded() >= 1_000
      ? "\((cutoffHz / 1_000).formatted(.number.precision(.fractionLength(1)))) kHz"
      : "\(Int(cutoffHz.rounded())) Hz"
  }

  private static func position(forHz hz: Double) -> Double {
    log(max(20, min(20_000, hz)) / 20) / log(1_000)
  }

  private func apply() {
    let cutoff = Float(cutoffHz)
    let changed =
      sound.synthFilterMode != mode || abs(sound.synthFilterCutoff - cutoff) > 0.5
      || abs(sound.synthFilterResonance - Float(resonance)) > 0.001
    guard changed else { return }
    sound.setSynthFilter(mode: mode, cutoff: cutoff, resonance: Float(resonance))
    onEdit?()
  }
}

#Preview("Synth Filter") {
  SoundPrototypeHarness { sound in
    Form {
      Section {
        SoundSynthFilter(sound: sound)
      } header: {
        Text(verbatim: "Filter")
      }
    }
  }
  .preferredColorScheme(.dark)
}
