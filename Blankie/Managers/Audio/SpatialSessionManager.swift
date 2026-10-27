//
//  SpatialSessionManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFAudio
import Combine
import Foundation
import os

/// Apple-style spatial mode: off, fixed in space, or following head motion.
enum SpatialSessionMode: String, CaseIterable {
  case off
  case fixed
  case headTracked
}

/// Holds the live spatial session. The mode resets to off on launch, and
/// placements are discarded when the session ends (nothing goes to presets).
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

  /// Whether audio routes to a car (CarPlay or car Bluetooth). Spatial
  /// sessions are headphone-only. The spatial render fails on a car route.
  static var isCarAudioRouteActive: Bool {
    #if os(iOS)
      return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
        $0.portType == .carAudio
      }
    #else
      return false
    #endif
  }

  /// Ends any live session when a car route/scene appears. No-op otherwise.
  @MainActor
  func endSessionForCarAudio() {
    guard isActive else { return }
    Logger.audio.debug("SpatialSession: ending session - car audio route")
    setMode(.off)
  }

  /// Switches mode. Entering or leaving a session rebuilds players (the spatial
  /// chain is decided at load). Fixed vs. head-tracked is only the env-node flag.
  @MainActor
  func setMode(_ newMode: SpatialSessionMode) {
    guard newMode != mode else { return }
    if newMode != .off, Self.isCarAudioRouteActive { return }
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

  /// Seeds an even fan around the listener when a session starts. Runs before
  /// the rebuild so players load straight into their spots.
  @MainActor
  private func seedDefaultSpread() {
    let sounds = AudioManager.shared.sounds.filter { $0.isSelected && $0.isSpatialReady }
    guard !sounds.isEmpty else { return }

    for (index, sound) in sounds.enumerated() {
      placements[sound.fileName] = Self.spreadSlot(index: index, count: sounds.count)
    }
  }

  /// The even-fan slot for sound `index` of `count`, shared by seeding, the
  /// mixer's Arrange action and its no-op check.
  static func spreadSlot(index: Int, count: Int) -> Placement {
    Placement(angle: Float(index) * (360.0 / Float(count)), distance: 2.0)
  }

  // MARK: - Session placements (in-memory only)

  func placement(for fileName: String) -> Placement? {
    placements[fileName]
  }

  @MainActor
  func setPlacement(angle: Float, distance: Float, for fileName: String) {
    placements[fileName] = Placement(angle: angle, distance: distance)
  }

  /// Whether the sound participates in the field this session.
  func isInField(_ fileName: String) -> Bool {
    !removedFromField.contains(fileName)
  }

  @MainActor
  func setInField(_ inField: Bool, for fileName: String) {
    if inField {
      removedFromField.remove(fileName)
    } else {
      removedFromField.insert(fileName)
    }
  }
}
