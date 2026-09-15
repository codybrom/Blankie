//
//  NowPlayingSessionMapping.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 session's pure mappings, kept free of the NowPlaying framework so
//  they compile (and are tested) without the 27 SDK.

import Foundation

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

/// Turns app state into the values the OS 27 session model publishes.
enum NowPlayingSessionMapping {

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
}
