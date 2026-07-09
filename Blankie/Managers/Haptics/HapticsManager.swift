//
//  HapticsManager.swift
//  Blankie
//
//  Created by Cody Bromley on 7/9/26.
//
//  The hand column's shared core (plan 011). Feature A — the sounds' haptic
//  voices — renders through Core Haptics: each family is a small composed
//  pattern with real character (a crackle pops, a wave swells, a train goes
//  chunk-chunk-chunk), not a single flat tap. A selection that used to fire the
//  generic `.sensoryFeedback(.selection)` tick now answers in the touched
//  sound's own voice. No new gesture surface — it decorates interactions that
//  already exist.
//
//  Two things make Core Haptics reliable here, both learned the hard way:
//    • The engine uses its OWN default session, never Blankie's active
//      `.playback` session — sharing an actively-playing audio session swallows
//      the haptic output entirely.
//    • Advanced players are RETAINED until their pattern finishes. A released
//      player cuts off anything longer than an instant, so a swell or a
//      multi-tap sequence would go silent mid-pattern.
//  If the engine can't start, a UIKit impact stands in so feedback never
//  vanishes.
//
//  iPhone-only by nature. iPad and Apple Vision Pro have no Taptic Engine
//  (`supportsHaptics` is false), so every entry point is a safe no-op; macOS
//  falls back to a standard trackpad tick.
//

import Foundation
import os

#if os(iOS)
  import CoreHaptics
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Central renderer for Blankie's custom haptics. Main-actor isolated: every
/// caller (SwiftUI views, managers) already runs on the main actor, and the
/// engine is created, stored, and driven from there.
@MainActor
final class HapticsManager {
  static let shared = HapticsManager()

  /// When the user last tapped a sound tile. A selection change is only given a
  /// haptic if it lands within `userWindow` of this — so the burst of
  /// programmatic changes from applying a preset (which never calls
  /// `noteUserToggle`) stays silent. That both avoids a haptic storm and keeps
  /// it from interrupting the audio session mid-preset-swap.
  private var lastUserToggle = Date.distantPast
  private let userWindow: TimeInterval = 0.3

  #if os(iOS)
    private var engine: CHHapticEngine?
    private var isRunning = false
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    /// Players kept alive for the duration of their pattern; a released player
    /// stops mid-pattern. Cleared by each player's completion handler.
    private var activePlayers: [Int: CHHapticAdvancedPatternPlayer] = [:]
    private var playerSeq = 0
    /// Global length multiplier for every voice — one knob to tune overall
    /// pattern duration. The patterns are authored at their natural shape; this
    /// shortens (or lengthens) them uniformly.
    private let timeScale: TimeInterval = 0.6
  #endif

  private init() {
    #if os(iOS)
      Logger.haptics.debug(
        "HapticsManager: init — supportsHaptics=\(self.supportsHaptics, privacy: .public)")
    #endif
  }

  /// Whether the user has custom touch feedback enabled. Governs the discrete
  /// haptic voices (feature A) and, later, the winding crank (feature B). The
  /// continuous ambient-haptics feature (C) gets its own separate opt-in.
  private var isEnabled: Bool {
    GlobalSettings.shared.touchFeedback
  }

  // MARK: - Feature A: selection voices

  /// Marks that the user just tapped a sound tile. Call this from tile tap
  /// handlers, before the toggle. Selection changes not preceded by a tap
  /// (applying a preset, launch restore, Quick Mix/solo cascades) get no haptic.
  func noteUserToggle() {
    lastUserToggle = Date()
  }

  /// Plays the given sound's selection voice — its composed pattern. Called when
  /// a sound tile toggles.
  func playSelection(for sound: Sound, selected: Bool) {
    guard isEnabled else {
      Logger.haptics.debug("HapticsManager: playSelection skipped — touch feedback off")
      return
    }
    // Only respond to changes the user just caused by tapping a tile. `onChange`
    // fires asynchronously after the mutation, so a synchronous "applying preset"
    // flag would already be cleared by now — the recent-tap window is what
    // reliably tells a user toggle apart from a programmatic burst.
    guard Date().timeIntervalSince(lastUserToggle) < userWindow else {
      Logger.haptics.debug("HapticsManager: selection change not user-initiated — skipped")
      return
    }
    // Deselect is a short, neutral "off" tick, not a replay of the whole voice —
    // the character belongs to turning a sound on.
    guard selected else {
      Logger.haptics.debug("HapticsManager: playOff")
      playOff()
      return
    }
    let voice = HapticVoice.voice(for: sound)
    Logger.haptics.debug(
      "HapticsManager: playSelection '\(sound.fileName, privacy: .public)' voice=\(voice.rawValue, privacy: .public)"
    )
    play(voice)
  }

  // MARK: - Playback

  private func play(_ voice: HapticVoice) {
    #if os(iOS)
      guard supportsHaptics else { return }
      guard let engine = startedEngine() else {
        fallbackImpact(for: voice)
        return
      }
      do {
        try start(try makePattern(for: voice), on: engine)
      } catch {
        Logger.haptics.error("HapticsManager: play failed: \(error, privacy: .public)")
        fallbackImpact(for: voice)
      }
    #elseif os(macOS)
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    #endif
  }

  /// A short but substantial "off" — a firm tap with a quick softer one behind
  /// it, descending, so it reads as a release/settle rather than a faint blip.
  /// Still much shorter than any voice.
  private func playOff() {
    #if os(iOS)
      guard supportsHaptics else { return }
      guard let engine = startedEngine() else {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return
      }
      do {
        let pattern = try CHHapticPattern(
          events: [
            transient(0, intensity: 0.8, sharpness: 0.45),
            transient(0.09, intensity: 0.55, sharpness: 0.3),
          ], parameters: [])
        try start(pattern, on: engine)
      } catch {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }
    #elseif os(macOS)
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    #endif
  }

  #if os(iOS)
    /// Plays a pattern and retains its player until the pattern finishes (a
    /// released advanced player stops mid-pattern).
    private func start(_ pattern: CHHapticPattern, on engine: CHHapticEngine) throws {
      let player = try engine.makeAdvancedPlayer(with: pattern)
      playerSeq += 1
      let key = playerSeq
      player.completionHandler = { [weak self] _ in
        Task { @MainActor in self?.activePlayers[key] = nil }
      }
      activePlayers[key] = player
      try player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: - Patterns

    /// The composed pattern for each voice. These are a starting structure —
    /// haptics are judged on a physical iPhone — so the shapes and values here
    /// are the owner's to tune on device.
    private func makePattern(for voice: HapticVoice) throws -> CHHapticPattern {
      switch voice {
      case .soft:
        // A soft breath that swells to a late crest and fades.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.4, intensity: 1, sharpness: 0.1)],
          parameterCurves: [intensityCurve([(0, 0), (0.26, 0.7), (0.4, 0)])])
      case .round:
        // A rolling swell that builds to a late crest and settles.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.62, intensity: 1, sharpness: 0.05)],
          parameterCurves: [
            intensityCurve([(0, 0.1), (0.3, 0.65), (0.46, 1.0), (0.62, 0.12)])
          ])
      case .wave:
        // A long sustained sigh — Ahhhhhhh. Rises to a held plateau, then a
        // long slow fade.
        return try CHHapticPattern(
          events: [continuous(0, duration: 1.0, intensity: 1, sharpness: 0.07)],
          parameterCurves: [
            intensityCurve([(0, 0.1), (0.22, 0.72), (0.42, 0.85), (0.72, 0.78), (1.0, 0.06)])
          ])
      case .crackle:
        // Irregular pops that build to a stronger burst at the end.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.55, sharpness: 0.9),
            transient(0.09, intensity: 0.75, sharpness: 0.95),
            transient(0.19, intensity: 0.6, sharpness: 0.85),
            transient(0.30, intensity: 0.85, sharpness: 0.95),
            transient(0.42, intensity: 0.7, sharpness: 0.9),
            transient(0.54, intensity: 1.0, sharpness: 0.95),
          ], parameters: [])
      case .mechanical:
        // A firm rhythm that builds — chunk, chunk, chunk, CHUNK.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.65, sharpness: 0.7),
            transient(0.12, intensity: 0.78, sharpness: 0.7),
            transient(0.24, intensity: 0.88, sharpness: 0.75),
            transient(0.36, intensity: 1.0, sharpness: 0.75),
          ], parameters: [])
      case .train:
        // Rolling stock over rail joints — ka-chunk, ka-chunk, ka-chunk. Each
        // pair is a light, sharp "ka" then a heavier, duller "chunk", with a
        // gap before the next pair.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.5, sharpness: 0.8),
            transient(0.07, intensity: 0.9, sharpness: 0.55),
            transient(0.26, intensity: 0.5, sharpness: 0.8),
            transient(0.33, intensity: 0.92, sharpness: 0.55),
            transient(0.52, intensity: 0.5, sharpness: 0.8),
            transient(0.59, intensity: 1.0, sharpness: 0.55),
          ], parameters: [])
      case .bright:
        // A rising chirp — three quick notes climbing.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.7, sharpness: 0.9),
            transient(0.08, intensity: 0.85, sharpness: 0.95),
            transient(0.17, intensity: 1.0, sharpness: 0.95),
          ], parameters: [])
      case .patter:
        // Pittery-pattery — light crisp droplets, well spread out, building a
        // little toward the end.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.35, sharpness: 0.9),
            transient(0.1, intensity: 0.4, sharpness: 0.85),
            transient(0.21, intensity: 0.3, sharpness: 0.95),
            transient(0.33, intensity: 0.5, sharpness: 0.85),
            transient(0.44, intensity: 0.42, sharpness: 0.9),
            transient(0.56, intensity: 0.55, sharpness: 0.85),
            transient(0.68, intensity: 0.6, sharpness: 0.85),
          ], parameters: [])
      case .thunder:
        // A peal of thunder: a slight tap acknowledging your touch, a beat, then
        // the crack — which rolls off in a long decaying rumble.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.6, sharpness: 0.55),  // acknowledgment
            transient(0.2, intensity: 1.0, sharpness: 0.85),  // the crack
            continuous(0.2, duration: 0.7, intensity: 1.0, sharpness: 0.1),  // the roll
          ],
          parameterCurves: [
            intensityCurve([
              (0, 0.45), (0.16, 0.3), (0.2, 1.0), (0.42, 0.55), (0.66, 0.26), (0.9, 0.0),
            ])
          ])
      case .flow:
        // A steady low hum — Mmmmmm. Quick rise to a warm plateau, holds, fades.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.85, intensity: 1, sharpness: 0.12)],
          parameterCurves: [
            intensityCurve([(0, 0.1), (0.12, 0.52), (0.32, 0.56), (0.62, 0.52), (0.85, 0.1)])
          ])
      case .gust:
        // A rising, falling howl — whoooOoooo. Swells to a strong mid-late peak
        // then tapers away.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.9, intensity: 1, sharpness: 0.13)],
          parameterCurves: [
            intensityCurve([(0, 0.05), (0.25, 0.4), (0.46, 0.92), (0.62, 0.6), (0.9, 0.05)])
          ])
      case .drone:
        // A soft, quiet, steady drone — hmmmmm. Low flat plateau, gentle in and
        // out; softer than the stream hum.
        return try CHHapticPattern(
          events: [continuous(0, duration: 1.0, intensity: 1, sharpness: 0.08)],
          parameterCurves: [
            intensityCurve([(0, 0.05), (0.18, 0.36), (0.4, 0.4), (0.8, 0.37), (1.0, 0.05)])
          ])
      case .fuzz:
        // Dense chaotic static — a fast random hiss of light, varied taps.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.5, sharpness: 0.7),
            transient(0.03, intensity: 0.35, sharpness: 0.95),
            transient(0.07, intensity: 0.6, sharpness: 0.8),
            transient(0.1, intensity: 0.4, sharpness: 1.0),
            transient(0.14, intensity: 0.55, sharpness: 0.75),
            transient(0.18, intensity: 0.38, sharpness: 0.95),
            transient(0.21, intensity: 0.62, sharpness: 0.85),
            transient(0.25, intensity: 0.42, sharpness: 1.0),
            transient(0.29, intensity: 0.52, sharpness: 0.7),
            transient(0.33, intensity: 0.4, sharpness: 0.95),
            transient(0.37, intensity: 0.58, sharpness: 0.85),
            transient(0.41, intensity: 0.45, sharpness: 1.0),
          ], parameters: [])
      case .wash:
        // A steady, brighter mid wash — green noise. Constant, holds, fades.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.8, intensity: 1, sharpness: 0.4)],
          parameterCurves: [
            intensityCurve([(0, 0.15), (0.12, 0.55), (0.6, 0.55), (0.8, 0.15)])
          ])
      case .whir:
        // A steady hum with a fine, fast blade flutter riding on top — a fan.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.72, intensity: 1, sharpness: 0.28)],
          parameterCurves: [
            intensityCurve([
              (0, 0.2), (0.1, 0.5), (0.18, 0.42), (0.26, 0.5), (0.34, 0.42), (0.42, 0.5),
              (0.5, 0.44), (0.72, 0.15),
            ])
          ])
      case .tumble:
        // A slow rolling sway — a washer drum turning over and over.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.9, intensity: 1, sharpness: 0.2)],
          parameterCurves: [
            intensityCurve([
              (0, 0.15), (0.2, 0.55), (0.4, 0.32), (0.6, 0.6), (0.8, 0.3), (0.9, 0.15),
            ])
          ])
      case .bustle:
        // A restless mid hum — distant traffic that never quite settles.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.72, intensity: 1, sharpness: 0.32)],
          parameterCurves: [
            intensityCurve([
              (0, 0.2), (0.12, 0.5), (0.24, 0.4), (0.36, 0.55), (0.5, 0.42), (0.72, 0.2),
            ])
          ])
      case .beat:
        // A lo-fi beat — boom, hat, tap, hat, boom.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 1.0, sharpness: 0.4),  // kick
            transient(0.14, intensity: 0.32, sharpness: 0.9),  // hat
            transient(0.28, intensity: 0.6, sharpness: 0.6),  // snare/tap
            transient(0.42, intensity: 0.32, sharpness: 0.9),  // hat
            transient(0.55, intensity: 1.0, sharpness: 0.4),  // kick
          ], parameters: [])
      case .pad:
        // A soft sustained swell — a held chord rising and settling.
        return try CHHapticPattern(
          events: [continuous(0, duration: 0.9, intensity: 1, sharpness: 0.22)],
          parameterCurves: [
            intensityCurve([(0, 0.05), (0.3, 0.5), (0.55, 0.6), (0.9, 0.05)])
          ])
      case .pluck:
        // A gentle pluck that rings and fades — a guitar string.
        return try CHHapticPattern(
          events: [
            transient(0, intensity: 0.75, sharpness: 0.5),
            continuous(0.01, duration: 0.4, intensity: 1, sharpness: 0.25),
          ],
          parameterCurves: [
            intensityCurve([(0, 0.55), (0.05, 0.5), (0.41, 0.0)])
          ])
      case .creak:
        // Slow, low, dull creaks — a boat rocking, well spread out.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.55, sharpness: 0.3),
            transient(0.28, intensity: 0.4, sharpness: 0.28),
            transient(0.6, intensity: 0.5, sharpness: 0.3),
          ], parameters: [])
      case .crickets:
        // Sparse paired chirps with long gaps — a summer night.
        return try CHHapticPattern(
          events: [
            transient(0.0, intensity: 0.4, sharpness: 0.95),
            transient(0.05, intensity: 0.32, sharpness: 0.95),
            transient(0.4, intensity: 0.4, sharpness: 0.95),
            transient(0.45, intensity: 0.32, sharpness: 0.95),
            transient(0.82, intensity: 0.4, sharpness: 0.95),
          ], parameters: [])
      case .neutral:
        // A single clean tap.
        return try CHHapticPattern(
          events: [transient(0, intensity: 0.9, sharpness: 0.5)], parameters: [])
      }
    }

    // The three builders below all fold in `timeScale`, so the pattern cases can
    // be authored at their natural timings and shortened uniformly by one knob.

    private func transient(_ time: TimeInterval, intensity: Float, sharpness: Float)
      -> CHHapticEvent
    {
      CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time * timeScale)
    }

    private func continuous(
      _ time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float
    ) -> CHHapticEvent {
      CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time * timeScale, duration: duration * timeScale)
    }

    /// An intensity envelope over a continuous event — the shape of a swell.
    private func intensityCurve(_ points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
      CHHapticParameterCurve(
        parameterID: .hapticIntensityControl,
        controlPoints: points.map {
          CHHapticParameterCurve.ControlPoint(relativeTime: $0.0 * timeScale, value: $0.1)
        },
        relativeTime: 0)
    }

    // MARK: - Engine lifecycle

    private func startedEngine() -> CHHapticEngine? {
      if engine == nil { engine = makeEngine() }
      guard let engine else { return nil }
      if !isRunning {
        do {
          try engine.start()
          isRunning = true
          Logger.haptics.debug("HapticsManager: engine started")
        } catch {
          Logger.haptics.error("HapticsManager: engine start failed: \(error, privacy: .public)")
          return nil
        }
      }
      return engine
    }

    private func makeEngine() -> CHHapticEngine? {
      do {
        // Plain engine with its own default session (NOT Blankie's `.playback`
        // session — sharing that swallowed haptic output). `playsHapticsOnly`
        // keeps it from reserving audio resources, so it never contends with
        // Blankie's audio.
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { [weak self] _ in
          Task { @MainActor in
            self?.isRunning = false
            self?.activePlayers.removeAll()
          }
        }
        engine.resetHandler = { [weak self] in
          Task { @MainActor in
            guard let self, let engine = self.engine else { return }
            self.activePlayers.removeAll()
            try? engine.start()
            self.isRunning = true
          }
        }
        Logger.haptics.debug("HapticsManager: engine created (default session, haptics-only)")
        return engine
      } catch {
        Logger.haptics.error("HapticsManager: engine creation failed: \(error, privacy: .public)")
        return nil
      }
    }

    /// Warm the engine when the app becomes active so the first tap is snappy.
    func handleBecameActive() {
      guard isEnabled, supportsHaptics else { return }
      _ = startedEngine()
    }

    /// Stop the engine on background (the system does this too); keeps our
    /// running flag honest and drops retained players.
    func stop() {
      guard let engine, isRunning else { return }
      isRunning = false
      activePlayers.removeAll()
      engine.stop()
    }

    /// UIKit impact used only when Core Haptics can't render — preserves
    /// feedback on the failure path with a rough sense of the voice.
    private func fallbackImpact(for voice: HapticVoice) {
      let style: UIImpactFeedbackGenerator.FeedbackStyle
      switch voice {
      case .soft, .flow, .gust, .drone, .wash, .whir, .tumble, .bustle, .pad, .creak, .neutral:
        style = .medium
      case .round, .wave, .thunder, .beat: style = .heavy
      case .crackle, .mechanical, .train: style = .rigid
      case .bright, .patter, .fuzz, .pluck, .crickets: style = .light
      }
      let generator = UIImpactFeedbackGenerator(style: style)
      generator.impactOccurred()
    }
  #else
    func handleBecameActive() {}
    func stop() {}
  #endif
}
