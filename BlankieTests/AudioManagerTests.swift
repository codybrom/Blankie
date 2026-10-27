//
//  AudioManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import Foundation
import Testing

@testable import Blankie

/// AudioManager selection, derived state and the play gate. Autoplay is off, so selecting
/// a sound never starts the engine. Serialized: drives the `AudioManager.shared` singleton.
@Suite(.serialized) @MainActor
struct AudioManagerTests {
  private let audioManager = AudioManager.shared

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    audioManager.resetSounds()
  }

  @Test func resetBaselineHasSoundsButIsNotPlaying() {
    #expect(!audioManager.isGloballyPlaying)
    #expect(!audioManager.sounds.isEmpty)
  }

  @Test func resetClearsSelectionAndVolume() {
    audioManager.sounds[0].isSelected = true
    audioManager.sounds[0].volume = 0.5

    audioManager.resetSounds()

    for sound in audioManager.sounds {
      #expect(!sound.isSelected)
      #expect(sound.volume == 0.75)
    }
  }

  /// Selection alone doesn't recompute `hasSelectedSounds`; the app calls
  /// `updateHasSelectedSounds` on change.
  @Test func selectionUpdatesHasSelectedSounds() {
    #expect(!audioManager.hasSelectedSounds)

    audioManager.sounds[0].isSelected = true
    audioManager.updateHasSelectedSounds()

    #expect(audioManager.hasSelectedSounds)
  }

  /// Remote commands (lock screen, Control Center, CarPlay) reach this path without
  /// the in-app selection check.
  @Test func playRequestWithoutSelectionStaysPaused() {
    #expect(!audioManager.hasSelectedSounds)

    audioManager.setGlobalPlaybackState(true)

    #expect(
      !audioManager.isGloballyPlaying, "A play request with no selected sounds must stay paused")
  }

  /// Siri intents and preset application play before the coalesced
  /// `hasSelectedSounds` updates.
  @Test func playGateSeesSelectionBeforeCoalescedFlag() {
    audioManager.sounds[0].isSelected = true

    #expect(!audioManager.hasSelectedSounds)
    #expect(audioManager.hasPlayableSelection)

    audioManager.sounds[0].isSelected = false
  }

  /// The auto-pause is dispatched to the main actor, so the test awaits it.
  @Test func deselectingLastSoundPausesPlayback() async {
    audioManager.sounds[0].isSelected = true
    audioManager.updateHasSelectedSounds()
    audioManager.isGloballyPlaying = true

    audioManager.sounds[0].isSelected = false
    audioManager.updateHasSelectedSounds()  // dispatches the auto-pause task

    for _ in 0..<100 where audioManager.isGloballyPlaying { await Task.yield() }
    #expect(!audioManager.isGloballyPlaying)

    audioManager.sounds[0].isSelected = false
  }

  @Test func deselectingOneOfManyKeepsPlaying() async {
    audioManager.sounds[0].isSelected = true
    audioManager.sounds[1].isSelected = true
    audioManager.updateHasSelectedSounds()
    audioManager.isGloballyPlaying = true

    audioManager.sounds[0].isSelected = false
    audioManager.updateHasSelectedSounds()

    for _ in 0..<20 { await Task.yield() }
    #expect(audioManager.isGloballyPlaying, "playback continues while a sound stays selected")

    audioManager.isGloballyPlaying = false
    audioManager.sounds[1].isSelected = false
  }

  /// An imported archive can repeat a name in `soundOrder`.
  @Test func orderingToleratesDuplicateSoundOrder() {
    let preset = PresetFactory.makePreset(soundOrder: ["rain", "waves", "rain"])
    #expect(audioManager.orderedVisibleSounds(for: preset).map(\.fileName) == ["rain", "waves"])
    #expect(audioManager.compositeSoundIcons(for: preset).count == 1)
  }
}
