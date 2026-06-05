//
//  SpatialSessionManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import Foundation
import os

/// Apple-style spatial mode: off, fixed in space, or following head motion.
enum SpatialSessionMode: String, CaseIterable {
  case off
  case fixed
  case headTracked
}

/// Holds the live spatial session. Deliberately volatile while the feature is
/// experimental: the mode resets to off on launch, and placements made in the
/// mixer are discarded when the session ends — nothing is written to presets.
final class SpatialSessionManager: ObservableObject {
  static let shared = SpatialSessionManager()

  struct Placement {
    var angle: Float
    var distance: Float
  }

  @Published private(set) var mode: SpatialSessionMode = .off
  @Published private(set) var placements: [String: Placement] = [:]
  @Published private(set) var removedFromField: Set<String> = []

  var isActive: Bool { mode != .off }

  private init() {}

  /// Switches mode. Entering/leaving a session rebuilds players (the spatial
  /// chain is decided at load); fixed ↔ head-tracked is just the env-node flag.
  @MainActor
  func setMode(_ newMode: SpatialSessionMode) {
    guard newMode != mode else { return }
    let wasActive = isActive
    mode = newMode
    Logger.audio.debug("SpatialSession: mode -> \(newMode.rawValue)")

    AudioEngineManager.shared.applyHeadTrackingSetting()

    if isActive != wasActive {
      if isActive {
        seedDefaultSpread()
      } else {
        placements.removeAll()
        removedFromField.removeAll()
      }
      AudioManager.shared.applySpatialAudioSetting()
    }
  }

  /// Seeds an even fan around the listener when a session starts (before the
  /// rebuild, so players load straight into their spots) — the hash defaults
  /// read as random clutter on first open.
  @MainActor
  private func seedDefaultSpread() {
    let sounds = AudioManager.shared.sounds.filter { $0.isSelected && $0.isSpatialReady }
    guard !sounds.isEmpty else { return }

    let step = 360.0 / Float(sounds.count)
    for (index, sound) in sounds.enumerated() {
      placements[sound.fileName] = Placement(angle: Float(index) * step, distance: 2.0)
    }
  }

  // MARK: - Session placements (in-memory only)

  func placement(for fileName: String) -> Placement? {
    placements[fileName]
  }

  func setPlacement(angle: Float, distance: Float, for fileName: String) {
    placements[fileName] = Placement(angle: angle, distance: distance)
  }

  /// Whether the sound participates in the field this session.
  func isInField(_ fileName: String) -> Bool {
    !removedFromField.contains(fileName)
  }

  func setInField(_ inField: Bool, for fileName: String) {
    if inField {
      removedFromField.remove(fileName)
    } else {
      removedFromField.insert(fileName)
    }
  }
}
