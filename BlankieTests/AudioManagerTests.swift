//
//  AudioManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import Foundation
import Testing

@testable import Blankie

/// State-machine tests for AudioManager — selection, derived state, and the
/// play gate. Deterministic and engine-free: autoplay is off and nothing is
/// globally playing, so selecting a sound never starts the audio engine (see
/// `Sound.isSelected.didSet`, which only plays while already playing). Real
/// playback is integration/on-device territory.
///
/// Serialized + main-actor because it drives the `AudioManager.shared` singleton.
/// Each test re-establishes its own baseline in `init`.
@Suite(.serialized) @MainActor
struct AudioManagerTests {
  private let audioManager = AudioManager.shared

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    audioManager.resetSounds()
  }

  /// A freshly reset manager has its sounds loaded but nothing playing.
  @Test func resetBaselineHasSoundsButIsNotPlaying() {
    #expect(!audioManager.isGloballyPlaying)
    #expect(!audioManager.sounds.isEmpty)
  }

  /// resetSounds clears every selection and restores the default per-sound volume.
  @Test func resetClearsSelectionAndVolume() {
    audioManager.sounds[0].isSelected = true
    audioManager.sounds[0].volume = 0.5

    audioManager.resetSounds()

    for sound in audioManager.sounds {
      #expect(!sound.isSelected)
      #expect(sound.volume == 0.75)
    }
  }

  /// Selecting a sound flips the derived `hasSelectedSounds` once the manager
  /// recomputes it — the precondition the play gate checks. (Selection alone
  /// doesn't recompute it; the app calls `updateHasSelectedSounds` on change.)
  @Test func selectionUpdatesHasSelectedSounds() {
    #expect(!audioManager.hasSelectedSounds)

    audioManager.sounds[0].isSelected = true
    audioManager.updateHasSelectedSounds()

    #expect(audioManager.hasSelectedSounds)
  }

  /// A play request with nothing selected must coerce to paused — silence must
  /// never read as "playing". Regression guard for the remote-command path
  /// (lock screen / Control Center / CarPlay) that bypassed the in-app check.
  @Test func playRequestWithoutSelectionStaysPaused() {
    #expect(!audioManager.hasSelectedSounds)

    audioManager.setGlobalPlaybackState(true)

    #expect(
      !audioManager.isGloballyPlaying, "A play request with no selected sounds must stay paused")
  }
}
