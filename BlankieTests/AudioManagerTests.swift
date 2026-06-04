//
//  AudioManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import XCTest

@testable import Blankie

@MainActor
final class AudioManagerTests: XCTestCase {
  var audioManager: AudioManager!

  override func setUp() async throws {
    try await super.setUp()
    audioManager = AudioManager.shared
    // Ensure we start with a clean state
    GlobalSettings.shared.setAutoPlayOnLaunch(true)
    audioManager.resetSounds()
  }

  override func tearDown() async throws {
    // Reset to default state
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    audioManager.resetSounds()
    try await super.tearDown()
  }

  func testInitialState() async throws {
    XCTAssertFalse(audioManager.isGloballyPlaying)
    XCTAssertFalse(audioManager.sounds.isEmpty)
  }

  func testTogglePlayback() async throws {
    // Setup: Select a sound and verify initial state
    XCTAssertFalse(audioManager.isGloballyPlaying)
    audioManager.sounds[0].isSelected = true

    // Test direct state changes
    audioManager.setGlobalPlaybackState(true)
    XCTAssertTrue(audioManager.isGloballyPlaying, "Should be playing after setting state to true")

    audioManager.setGlobalPlaybackState(false)
    XCTAssertFalse(
      audioManager.isGloballyPlaying, "Should not be playing after setting state to false")
  }

  func testResetSounds() async throws {
    // Select some sounds and adjust volumes
    audioManager.sounds[0].isSelected = true
    audioManager.sounds[0].volume = 0.5

    audioManager.resetSounds()

    // Verify all sounds are reset
    for sound in audioManager.sounds {
      XCTAssertFalse(sound.isSelected)
      XCTAssertEqual(sound.volume, 0.75)
    }
  }
}
