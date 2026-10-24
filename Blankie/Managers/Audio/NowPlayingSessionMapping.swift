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

  /// Timing captured at one instant so the system can extrapolate between
  /// publishes, whether the source is a sleep timer or an audio loop.
  nonisolated struct SessionProgress: Equatable {
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
  ) -> SessionProgress? {
    guard isActive, selectedDuration > 0 else { return nil }
    let elapsed = min(max(0, selectedDuration - remainingTime), selectedDuration)
    return SessionProgress(duration: selectedDuration, elapsed: elapsed, timestamp: now)
  }

  /// Loop progress is opt-in; very short or invalid loops remain indeterminate.
  nonisolated static func loopProgress(
    continuous: Bool, elapsed: TimeInterval, duration: TimeInterval, now: Date
  ) -> SessionProgress? {
    guard !continuous, elapsed.isFinite, duration.isFinite, duration >= 1 else { return nil }
    return SessionProgress(
      duration: duration, elapsed: min(duration, max(0, elapsed)), timestamp: now)
  }

  /// A sleep timer always wins over loop progress, including in continuous mode.
  nonisolated static func duration(timer: SessionProgress?, loop: SessionProgress? = nil)
    -> SessionDuration
  {
    guard let progress = timer ?? loop else { return .continuous }
    return .finite(progress.duration)
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

  /// The system reads a content item's duration once per id, so a running sleep
  /// timer publishes under a distinct id and the card re-reads its finite length.
  /// The id carries the length, so adding time arrives as a new item too.
  nonisolated static func contentID(
    _ base: String, timerDuration: TimeInterval?, loopDuration: TimeInterval? = nil
  ) -> String {
    if let timerDuration { return "\(base):timed:\(Int(timerDuration.rounded()))" }
    if let loopDuration { return "\(base):loop:\(loopDuration)" }
    return base
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
