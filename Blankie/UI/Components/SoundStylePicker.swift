//
//  SoundStylePicker.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import SwiftUI

/// SPIKE: a named treatment for one sound. Each is a fixed setting of the tone
/// shelves and the synth-style filter. Names are placeholders.
enum SoundStyle: String, CaseIterable, Identifiable {
  case original
  case smooth
  case clear
  case deep
  case light
  case nextRoom
  case oldRadio
  case seashell

  var id: String { rawValue }

  var name: String {
    switch self {
    case .original: "Original"
    case .smooth: "Smooth"
    case .clear: "Clear"
    case .deep: "Deep"
    case .light: "Light"
    case .nextRoom: "Next Room"
    case .oldRadio: "Old Radio"
    case .seashell: "Seashell"
    }
  }

  /// Tone shelves, each -1...1.
  var tone: (highs: Float, lows: Float) {
    switch self {
    case .smooth: (-0.6, 0)
    case .clear: (0.8, 0)
    case .deep: (0, 0.9)
    case .light: (0, -0.7)
    case .oldRadio: (-0.7, 0)
    case .original, .nextRoom, .seashell: (0, 0)
    }
  }

  var filter: (mode: SynthFilterMode, cutoff: Float, resonance: Float) {
    switch self {
    case .nextRoom: (.lowPass, 700, 0)
    case .oldRadio: (.highPass, 450, 0.35)
    case .seashell: (.lowPass, 900, 0.85)
    case .original, .smooth, .clear, .deep, .light: (.off, 1_000, 0)
    }
  }

  @MainActor
  func apply(to sound: Sound) {
    sound.setTone(highs: tone.highs, lows: tone.lows)
    sound.setSynthFilter(mode: filter.mode, cutoff: filter.cutoff, resonance: filter.resonance)
  }

  /// The style whose settings match the sound right now, if any.
  @MainActor
  static func current(for sound: Sound) -> SoundStyle? {
    allCases.first { style in
      style.tone.highs == sound.toneHighs && style.tone.lows == sound.toneLows
        && style.filter.mode == sound.synthFilterMode
        && (style.filter.mode == .off
          || (style.filter.cutoff == sound.synthFilterCutoff
            && style.filter.resonance == sound.synthFilterResonance))
    }
  }
}

/// SPIKE: pick a named style for a sound, with the filter sliders tucked behind
/// a disclosure for people who want them. Editing a slider clears the checkmark.
/// Emits form sections, so it goes inside a `Form`. Throwaway: no persistence.
struct SoundStylePicker: View {
  let sound: Sound

  @State private var selection: SoundStyle? = .original
  /// Bumped when a style is picked, so the sliders reload from the sound.
  @State private var filterRevision = 0

  var body: some View {
    Section {
      Picker(selection: $selection) {
        ForEach(SoundStyle.allCases) { style in
          Text(verbatim: style.name).tag(Optional(style))
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } header: {
      Text(verbatim: "Style")
    }
    .onAppear {
      selection = SoundStyle.current(for: sound)
    }
    .onChange(of: selection) { _, style in
      guard let style else { return }
      style.apply(to: sound)
      filterRevision += 1
    }
    .sensoryFeedback(.selection, trigger: selection)

    Section {
      DisclosureGroup {
        SoundSynthFilter(sound: sound) {
          selection = nil
        }
        .id(filterRevision)
      } label: {
        Text(verbatim: "Filter")
      }
    }
  }
}

#Preview("Styles") {
  SoundPrototypeHarness { sound in
    Form {
      SoundStylePicker(sound: sound)
    }
  }
  .preferredColorScheme(.dark)
}
