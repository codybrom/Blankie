//
//  TestSound.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  A Sound whose loadSound() never creates a player, so play()/pause()/reset
//  are safe no-ops (they all guard on `player`). Lets tests drive AudioManager's
//  selection, solo, Quick Mix, and music-exclusivity state machines without
//  touching the real audio engine. The `isMusic` / `isCustom` flags are settable
//  for the music-tag and built-in-only paths, `customSoundDataID` links a
//  custom stand-in to its SwiftData row, and `stubbedDuration` fakes a length.
//

import Foundation

@testable import Blankie

final class TestSound: Sound {
  /// Stands in for the player's duration, which an engine-free sound lacks.
  var stubbedDuration: TimeInterval?

  init(
    fileName: String, isMusic: Bool = false, isCustom: Bool = false,
    customSoundDataID: UUID? = nil
  ) {
    super.init(
      title: fileName,
      systemIconName: "speaker.wave",
      fileName: fileName,
      fileExtension: "m4a",
      isMusic: isMusic,
      isCustom: isCustom,
      customSoundDataID: customSoundDataID)
  }

  override var playbackDuration: TimeInterval { stubbedDuration ?? super.playbackDuration }

  override func loadSound() {
    // Intentionally empty: no player, so the sound stays engine-free.
  }
}
