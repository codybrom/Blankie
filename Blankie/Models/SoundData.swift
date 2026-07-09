//
//  SoundData.swift
//  Blankie
//
//  Created by Cody Bromley on 1/10/25.
//

import Foundation

nonisolated enum SoundMood: String, Codable, CaseIterable {
  case focus
  case sleep
  case relax

  var displayName: String {
    switch self {
    case .focus: return "Focus"
    case .sleep: return "Sleep"
    case .relax: return "Relax"
    }
  }

  var icon: String {
    switch self {
    case .focus: return "brain.head.profile"
    case .sleep: return "moon.stars.fill"
    case .relax: return "leaf.fill"
    }
  }
}

struct SoundData: Codable {
  let defaultOrder: Int
  let title: String
  let systemIconName: String
  let fileName: String
  let author: String
  let authorUrl: String?
  let license: String
  let soundUrl: String
  let soundName: String
  let subtitle: String?
  let description: String?
  let note: String?
  let lufs: Float?
  let normalizationFactor: Float?
  let moods: [SoundMood]?
  let duration: TimeInterval?
  let truePeakdBTP: Float?
  let needsLimiter: Bool?
  let isMusic: Bool?
  /// Named haptic voice (plan 011, feature A) — the sound's felt character when
  /// touched: "soft", "round", "crackle", "mechanical", "bright", or "neutral".
  /// Absent falls back to "neutral". See `HapticVoice`.
  let hapticVoice: String?
}

struct SoundsContainer: Codable {
  let sounds: [SoundData]
}
