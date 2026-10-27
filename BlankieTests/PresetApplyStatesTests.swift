//
//  PresetApplyStatesTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  applySoundStates suppresses per-sound music exclusivity, so its final sanitize pass is what
//  collapses an imported preset with several selected music sounds to one.
//  Serialized: drives AudioManager.shared with synthetic test-* sounds.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class PresetApplyStatesTests {
  private let audioManager = AudioManager.shared
  private let originalSounds: [Sound]

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalSounds = audioManager.sounds
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
  }
  isolated deinit {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    audioManager.sounds = originalSounds
  }

  @Test func applySanitizesMultipleMusicToOne() {
    let m1 = TestSound(fileName: "test-music-1", isMusic: true)
    let m2 = TestSound(fileName: "test-music-2", isMusic: true)
    let ambient = TestSound(fileName: "test-ambient", isMusic: false)
    audioManager.sounds = [m1, m2, ambient]

    PresetManager.shared.applySoundStates([
      PresetState(fileName: "test-music-1", isSelected: true, volume: 0.5),
      PresetState(fileName: "test-music-2", isSelected: true, volume: 0.5),
      PresetState(fileName: "test-ambient", isSelected: true, volume: 0.5),
    ])

    #expect(!m1.isSelected, "the earlier music sound is dropped")
    #expect(m2.isSelected, "the music sound appearing last in order is kept")
    #expect(ambient.isSelected, "a non-music sound is unaffected")
  }
}
