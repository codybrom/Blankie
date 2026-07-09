//
//  HapticVoice.swift
//  Blankie
//
//  Created by Cody Bromley on 7/9/26.
//
//  The per-sound haptic grammar (plan 011, feature A). Each built-in sound names
//  a voice in sounds.json (`hapticVoice`); `HapticsManager` turns that name into
//  a Core Haptics pattern with real character — a crackle that pops, a wave that
//  swells, a train that goes chunk-chunk-chunk. This type is just the identity
//  and the lookup; the actual patterns live in `HapticsManager` (they're
//  Core Haptics events, iOS-only, so they can't live in this platform-neutral
//  file).
//
//  The assignment (which sound is which voice) lives in sounds.json alongside
//  the sound's other metadata. Custom sounds and any unrecognized name fall back
//  to the neutral voice.
//

import Foundation

/// A sound's felt character. Maps to a Core Haptics pattern (and a UIKit impact
/// fallback) in `HapticsManager`.
enum HapticVoice: String {
  /// Fine and gentle — a soft breath. Summer night, forest.
  case soft
  /// Low and rolling — boat, deep noise, airplane. A swell that rises and falls.
  case round
  /// A long sustained sigh — Ahhhhhhh. Waves: rises to a held plateau and fades.
  case wave
  /// Irregular pops — fireplace, something catching. Snap-snap-pop.
  case crackle
  /// A firm rhythm — a fan, a washer. Chunk-chunk-chunk.
  case mechanical
  /// Rolling stock over rail joints — ka-chunk, ka-chunk. A train.
  case train
  /// A quick bright flurry — birds, a café, a plucked string, keys.
  case bright
  /// Pittery-pattery — rain. Many light scattered droplet taps.
  case patter
  /// A crack of thunder then a rolling rumble — storm.
  case thunder
  /// A steady low hum — Mmmmmm. A stream: warm, sustained, barely moving.
  case flow
  /// A rising, falling howl — whoooOoooo. Wind, a gust that swells and tapers.
  case gust
  /// A soft, quiet, steady drone — hmmmmm. Airplane: softer than the stream hum.
  case drone
  /// Dense chaotic static — a fast, random hiss of taps. White/pink noise.
  case fuzz
  /// A steady mid wash — green noise. Brighter and more constant than a hum.
  case wash
  /// A steady whir with a fine blade flutter — a fan.
  case whir
  /// A slow rolling tumble — a washer/dryer drum turning over.
  case tumble
  /// A restless mid hum — distant city traffic.
  case bustle
  /// A lo-fi beat — boom, tick, tap, tick, boom. Lo-Fi Beats.
  case beat
  /// A soft sustained swell — a held pad or chord. Ambient synth, warm piano.
  case pad
  /// A gentle pluck that rings and fades — an acoustic guitar string.
  case pluck
  /// Slow, low, dull creaks — a boat rocking at its mooring.
  case creak
  /// Sparse light chirps with long gaps — crickets on a summer night.
  case crickets
  /// The neutral default — any custom sound with no known voice.
  case neutral

  /// The voice for a sound, from its JSON-supplied `hapticVoiceName` (custom
  /// sounds carry neutral). An unrecognized name also falls back to neutral, so
  /// a typo in the catalog degrades quietly.
  static func voice(for sound: Sound) -> HapticVoice {
    HapticVoice(rawValue: sound.hapticVoiceName) ?? .neutral
  }
}
