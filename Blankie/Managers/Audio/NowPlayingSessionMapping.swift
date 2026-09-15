//
//  NowPlayingSessionMapping.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 session's pure mappings, kept free of the NowPlaying framework so
//  they compile (and are tested) without the 27 SDK.

import Foundation

/// Turns app state into the values the OS 27 session model publishes.
enum NowPlayingSessionMapping {

  // MARK: - Value types

  /// Whether the session reads as playing or paused.
  nonisolated enum SessionPlayback: Equatable {
    case playing
    case paused
  }

  /// How long the session's content runs: ambient mixes never end, a sleep timer does.
  nonisolated enum SessionDuration: Equatable {
    case continuous
    case finite(TimeInterval)
  }

  /// A running sleep timer's progress, with elapsed and timestamp captured at the
  /// same instant so the system can extrapolate between publishes.
  nonisolated struct SessionTimer: Equatable {
    let duration: TimeInterval
    let elapsed: TimeInterval
    let timestamp: Date
  }

  /// The animated-artwork shapes a lock screen can ask for, mirrored off the
  /// framework so the choice is testable without the 27 SDK.
  nonisolated enum SessionAspectRatio: Hashable {
    case square
    case tall
  }

  /// Where a piece of static artwork came from — everything that decides which
  /// image gets rendered, and nothing about how it is drawn.
  nonisolated enum ArtworkSource: Equatable {
    case stored(UUID)
    case file(String)
    case bundled(String)
    case solo(fileName: String)
    case fallback(kind: String, icons: [String])
  }

  // MARK: - Playback and timing

  nonisolated static func playback(isPlaying: Bool) -> SessionPlayback {
    isPlaying ? .playing : .paused
  }

  /// The sleep timer's progress, or nil when no timer is counting down.
  nonisolated static func timer(
    isActive: Bool,
    selectedDuration: TimeInterval,
    remainingTime: TimeInterval,
    now: Date
  ) -> SessionTimer? {
    guard isActive, selectedDuration > 0 else { return nil }
    let elapsed = min(max(0, selectedDuration - remainingTime), selectedDuration)
    return SessionTimer(duration: selectedDuration, elapsed: elapsed, timestamp: now)
  }

  /// Ambient playback is continuous; only a sleep timer gives it an end.
  nonisolated static func duration(timer: SessionTimer?) -> SessionDuration {
    guard let timer else { return .continuous }
    return .finite(timer.duration)
  }

  // MARK: - Identity

  /// The published content's identity. Stable across incremental updates
  /// (volume, play/pause) so the system doesn't treat the card as a new item.
  nonisolated static func contentID(
    soloFileName: String?,
    isQuickMix: Bool,
    presetID: UUID?
  ) -> String {
    if let soloFileName {
      return "solo:\(soloFileName)"
    } else if isQuickMix {
      return "quickmix"
    } else if let presetID {
      return "preset:\(presetID.uuidString)"
    } else {
      return "default"
    }
  }

  /// The artwork's identity. The system caches artwork by id and never asks for
  /// a cached one again, so this has to change whenever the rendered image
  /// would — which for the drawn fallbacks means folding in the accent and the
  /// icons they montage.
  nonisolated static func artworkID(source: ArtworkSource, accentColorName: String?) -> String {
    let accent = accentColorName ?? "default"
    switch source {
    case .stored(let id):
      return "artwork:\(id.uuidString)"
    case .file(let path):
      return "static:\(path)"
    case .bundled(let id):
      return "bundled:\(id)"
    case .solo(let fileName):
      return "solo:\(fileName):\(accent)"
    case .fallback(let kind, let icons):
      return "fallback:\(kind):\(accent):\(icons.joined(separator: ","))"
    }
  }

  /// The aspect ratios to publish: the ones this device supports that we also
  /// have a loop for, in the device's own order of preference.
  nonisolated static func supportedRatios(
    compatible: [SessionAspectRatio],
    available: Set<SessionAspectRatio>
  ) -> [SessionAspectRatio] {
    compatible.filter { available.contains($0) }
  }

  /// The animated artwork's identity. Bundled artwork has no Documents loop
  /// path, so its bundled id stands in; a preset with neither falls back to its
  /// own id.
  nonisolated static func animatedArtworkID(loopKey: String?, presetID: UUID) -> String {
    loopKey ?? presetID.uuidString
  }
}
