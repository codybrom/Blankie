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
//  for the music-tag and built-in-only paths.
//

import Foundation

@testable import Blankie

final class TestSound: Sound {
  init(fileName: String, isMusic: Bool = false, isCustom: Bool = false) {
    super.init(
      title: fileName,
      systemIconName: "speaker.wave",
      fileName: fileName,
      fileExtension: "m4a",
      isMusic: isMusic,
      isCustom: isCustom)
  }

  override func loadSound() {
    // Intentionally empty: no player, so the sound stays engine-free.
  }
}
