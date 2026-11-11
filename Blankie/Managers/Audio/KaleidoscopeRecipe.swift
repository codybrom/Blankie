//
//  KaleidoscopeRecipe.swift
//  Blankie
//
//  Created by Cody Bromley on 11/2/26.
//

import Foundation
import os

/// A Kaleidoscope, decoded from a file in `Resources/Kaleidoscope`: a stack of
/// layers, each a group of tones with its own tuning. A tone's motion is the sum of
/// its layer's arc, its own wander and a wobble grown from the layer's seed.
struct KaleidoscopeRecipe: Decodable, Sendable {
  var title: String
  var fileName: String
  /// Any word or phrase. The same seed always grows the same glass for the sound's
  /// picture: its colors, its mirrors and its pieces. Without one, the file name is used.
  var glassSeed: String?
  var systemIconName: String
  var lufs: Float
  var source: Source
  /// Seconds each play takes to swell in from silence.
  var attackSec: Double
  /// How fast the tones drift from side to side: 1 is the standard pace.
  var driftSpeed = 1.0
  /// Seconds the right ear hears each layer's motion after the left.
  var earLagSec = 3.7
  /// Seconds before the motion repeats.
  var loopSec: Int
  var layers: [Layer]

  /// The recording the tones were measured from, credited like a built-in sound.
  struct Source: Decodable, Sendable {
    var title: String
    var author: String
    var license: String
    var url: String
  }

  /// One register of the sound. The defaults play its motion as written.
  struct Layer: Decodable, Sendable {
    var name: String
    /// Volume trim for the whole layer.
    var gainDB = 0.0
    /// How far the tones swell and fade: 0 holds them steady, 1 is as measured.
    var motionDepth = 1.0
    /// How fast the motion plays: 1 is as measured, 0.5 takes twice as long.
    var motionSpeed = 1.0
    /// Each tone plays as two voices, this far below and above its pitch. Wider
    /// detune makes the tones swirl between the ears faster.
    var detuneCents = 6.0
    /// How far the tones drift from center: 0 stays put, 1 is widest.
    var panWidth = 0.8
    /// The slow swell every tone in the layer shares, as points spread evenly
    /// across the loop.
    var arc: [Double] = []
    /// How strongly the tones follow the arc: 0 ignores it, 1 is as written.
    var arcDepth = 1.0
    /// How far each tone strays from the arc on its own slow path.
    var wanderDepth = 1.0
    /// How much each tone flickers from second to second.
    var wobbleDepth = 1.0
    /// Any word or phrase. The same seed always grows the same flicker, and a new
    /// one grows a new pattern of the same size and pace.
    var wobbleSeed = ""
    /// How quickly the flicker changes: smaller is busier.
    var wobblePaceSec = 7.0
    var tones: [Tone]
  }

  /// One sine tone. `db` is its average level, relative to the sound's loudest tone.
  struct Tone: Decodable, Sendable {
    var hz: Double
    var db: Double
    /// The tone's own slow path around the layer's arc, as points spread evenly
    /// across the loop.
    var wander: [Double] = []
    /// How far the tone's flicker typically swings, in decibels.
    var wobbleDB = 0.0
    /// A hand-written flicker, one value a second. It replaces the grown one.
    var wobble: [Double] = []

    /// The tone's loudness each second of the loop, as gain. Empty holds it steady.
    /// `index` is the tone's place in its layer, so each tone grows its own flicker.
    nonisolated func motion(in layer: Layer, index: Int, loopSec: Int) -> [Float] {
      var flicker = wobble
      if flicker.isEmpty, wobbleDB > 0 {
        let points = layer.arc.isEmpty ? max(1, loopSec / 15) : layer.arc.count
        flicker = Self.grownWobble(
          seed: "\(layer.wobbleSeed)#\(index)", loopSec: loopSec,
          paceSec: layer.wobblePaceSec, slowPoints: points
        ).map { $0 * wobbleDB }
      }
      guard loopSec > 0, !(layer.arc.isEmpty && wander.isEmpty && flicker.isEmpty) else { return [] }
      let gains = (0..<loopSec).map { second -> Double in
        let position = Double(second) / Double(loopSec)
        let decibels =
          layer.arcDepth * Self.value(of: layer.arc, at: position)
          + layer.wanderDepth * Self.value(of: wander, at: position)
          + layer.wobbleDepth * (second < flicker.count ? flicker[second] : 0)
        return pow(10, decibels / 20)
      }
      // Motion reshapes a tone without changing its average power, so `db` stays true.
      let power = gains.reduce(0) { $0 + $1 * $1 } / Double(loopSec)
      return gains.map { Float($0 / max(power.squareRoot(), 1e-9)) }
    }

    /// Grows a looping flicker from a seed, one value a second, averaging zero with a
    /// typical swing of 1. It is the loudness of smoothed noise, which is how a real
    /// tone's level flickers, with the slow part left to the arc and wander.
    nonisolated static func grownWobble(
      seed: String, loopSec: Int, paceSec: Double, slowPoints: Int
    ) -> [Double] {
      guard loopSec > 1 else { return [Double](repeating: 0, count: max(0, loopSec)) }
      // FNV-1a turns the seed into the generator's starting state.
      var state = seed.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
      func gaussian() -> Double {
        let radius = sqrt(-2 * log(max(KaleidoscopePlayer.nextUnit(&state), 1e-12)))
        return radius * cos(2 * .pi * KaleidoscopePlayer.nextUnit(&state))
      }
      let noise = (0..<loopSec).map { _ in (gaussian(), gaussian()) }
      let pace = max(1, paceSec)
      let reach = Int((pace / 2).rounded(.up))
      var decibels = [Double](repeating: 0, count: loopSec)
      for second in 0..<loopSec {
        var real = 0.0
        var imaginary = 0.0
        for offset in -reach...reach where abs(Double(offset)) <= pace / 2 {
          let weight = 0.5 + 0.5 * cos(2 * .pi * Double(offset) / pace)
          let sample = noise[((second - offset) % loopSec + loopSec) % loopSec]
          real += weight * sample.0
          imaginary += weight * sample.1
        }
        decibels[second] = 20 * log10((real * real + imaginary * imaginary).squareRoot() + 1e-9)
      }
      // Remove the slow part: each point is the average of the seconds around it.
      let pointCount = max(1, slowPoints)
      let half = Int((Double(loopSec) / Double(pointCount) / 2).rounded())
      let slow = (0..<pointCount).map { point -> Double in
        let center = Int((Double(point) * Double(loopSec) / Double(pointCount)).rounded())
        let window = (-half...half).map { decibels[((center + $0) % loopSec + loopSec) % loopSec] }
        return window.reduce(0, +) / Double(window.count)
      }
      for second in 0..<loopSec {
        decibels[second] -= value(of: slow, at: Double(second) / Double(loopSec))
      }
      let mean = decibels.reduce(0, +) / Double(loopSec)
      let spread = (decibels.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(loopSec)).squareRoot()
      return decibels.map { ($0 - mean) / max(spread, 1e-9) }
    }

    /// Reads looping points at a position from 0 to 1, gliding between neighbors.
    nonisolated static func value(of points: [Double], at position: Double) -> Double {
      guard !points.isEmpty else { return 0 }
      let scaled = position * Double(points.count)
      let index = Int(scaled) % points.count
      let frac = scaled - floor(scaled)
      return points[index] * (1 - frac) + points[(index + 1) % points.count] * frac
    }
  }

  /// Low to high register, which is also their default order.
  static let bundledFileNames = [
    "undertone", "depth", "haze", "calm", "stillness", "dawn", "gentleness", "lull", "velvet",
    "dreaming", "warmth", "hush", "radiance", "air", "mist",
  ]

  /// The recipes in the main bundle, decoded once. Empty where they aren't bundled
  /// (the widget extension).
  static let bundled: [KaleidoscopeRecipe] = bundledFileNames.compactMap { name -> KaleidoscopeRecipe? in
    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
    do {
      return try JSONDecoder().decode(KaleidoscopeRecipe.self, from: Data(contentsOf: url))
    } catch {
      Logger.audio.error(
        "KaleidoscopeRecipe: Failed to decode '\(name, privacy: .public)': \(error, privacy: .public)"
      )
      return nil
    }
  }
}

// MARK: - Decoding

extension KaleidoscopeRecipe.Layer {
  private enum CodingKeys: String, CodingKey {
    case name, gainDB, motionDepth, motionSpeed, detuneCents, panWidth, tones
    case arc, arcDepth, wanderDepth, wobbleDepth, wobbleSeed, wobblePaceSec
  }

  /// Any tuning value left out of the file keeps its default.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    tones = try container.decode([KaleidoscopeRecipe.Tone].self, forKey: .tones)
    gainDB = try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? gainDB
    motionDepth = try container.decodeIfPresent(Double.self, forKey: .motionDepth) ?? motionDepth
    motionSpeed = try container.decodeIfPresent(Double.self, forKey: .motionSpeed) ?? motionSpeed
    detuneCents = try container.decodeIfPresent(Double.self, forKey: .detuneCents) ?? detuneCents
    panWidth = try container.decodeIfPresent(Double.self, forKey: .panWidth) ?? panWidth
    arc = try container.decodeIfPresent([Double].self, forKey: .arc) ?? arc
    arcDepth = try container.decodeIfPresent(Double.self, forKey: .arcDepth) ?? arcDepth
    wanderDepth = try container.decodeIfPresent(Double.self, forKey: .wanderDepth) ?? wanderDepth
    wobbleDepth = try container.decodeIfPresent(Double.self, forKey: .wobbleDepth) ?? wobbleDepth
    wobbleSeed = try container.decodeIfPresent(String.self, forKey: .wobbleSeed) ?? wobbleSeed
    wobblePaceSec =
      try container.decodeIfPresent(Double.self, forKey: .wobblePaceSec) ?? wobblePaceSec
  }
}

extension KaleidoscopeRecipe.Tone {
  private enum CodingKeys: String, CodingKey {
    case hz, db, wander, wobbleDB, wobble
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hz = try container.decode(Double.self, forKey: .hz)
    db = try container.decode(Double.self, forKey: .db)
    wander = try container.decodeIfPresent([Double].self, forKey: .wander) ?? []
    wobbleDB = try container.decodeIfPresent(Double.self, forKey: .wobbleDB) ?? 0
    wobble = try container.decodeIfPresent([Double].self, forKey: .wobble) ?? []
  }
}
