//
//  SoundEqualizer.swift
//  Blankie
//
//  Created by Cody Bromley on 11/24/26.
//

import AVFoundation

/// The seven-band graphic equalizer on every sound's gain stage. Bands are wide
/// enough to overlap their neighbors.
enum SoundEqualizer {
  /// Band center frequencies in Hz, low to high.
  nonisolated static let frequencies: [Float] = [60, 150, 400, 1_000, 2_400, 6_000, 15_000]
  /// Each band moves this many dB either way.
  nonisolated static let rangeDB: Float = 18
  nonisolated static let flat = [Float](repeating: 0, count: frequencies.count)

  /// Clamps saved or imported gains to the band range. Returns nil for a flat
  /// curve or anything that isn't one finite value per band.
  nonisolated static func sanitized(_ gains: [Float]?) -> [Float]? {
    guard let gains, gains.count == frequencies.count, gains.allSatisfy(\.isFinite) else {
      return nil
    }
    let clamped = gains.map { max(-rangeDB, min(rangeDB, $0)) }
    return clamped.contains { abs($0) > 0.1 } ? clamped : nil
  }

  /// Offsets the average band gain so a curve that boosts doesn't get louder
  /// overall and one that cuts doesn't drop away.
  nonisolated static func loudnessTrimDB(for gains: [Float]) -> Float {
    guard !gains.isEmpty else { return 0 }
    let mean = gains.reduce(0, +) / Float(gains.count)
    return max(-9, min(6, -0.8 * mean))
  }

  /// An EQ unit with one bypassed band per frequency.
  static func makeUnit() -> AVAudioUnitEQ {
    let unit = AVAudioUnitEQ(numberOfBands: frequencies.count)
    unit.globalGain = 0
    for band in unit.bands { band.bypass = true }
    return unit
  }

  /// Sets every band on `unit` and returns the loudness trim in dB. Bands left
  /// at 0 dB are bypassed.
  static func apply(_ gains: [Float], to unit: AVAudioUnitEQ) -> Float {
    let gains = sanitized(gains) ?? flat
    for (index, band) in unit.bands.prefix(frequencies.count).enumerated() {
      let gainDB = gains[index]
      guard abs(gainDB) > 0.1 else {
        band.bypass = true
        continue
      }
      band.filterType = .parametric
      band.frequency = frequencies[index]
      band.bandwidth = 1.6
      band.gain = gainDB
      band.bypass = false
    }
    return loudnessTrimDB(for: gains)
  }
}
