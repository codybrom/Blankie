//
//  SoundTests.swift
//  Blankie
//
//  Created by Cody Bromley on 1/10/25.
//

import XCTest

@testable import Blankie

class MockSound: Sound {
  init(
    title: String, systemIconName: String, fileName: String, fileExtension: String = "mp3"
  ) {
    super.init(
      title: title, systemIconName: systemIconName, fileName: fileName, fileExtension: fileExtension
    )
  }

  override func loadSound() {
    // Don't actually load sound file in tests
    player = nil
  }
}

class SoundTests: XCTestCase {
  var sound: MockSound!

  override func setUp() {
    super.setUp()
    // Create a new instance for each test
    sound = MockSound(title: "Test Sound", systemIconName: "speaker.wave", fileName: "test")
  }

  override func tearDown() async throws {
    sound = nil
    try await super.tearDown()
  }

  func testInitialState() {
    // Create a fresh instance to test initial state
    let newSound = MockSound(title: "Fresh Test", systemIconName: "speaker.wave", fileName: "test")
    XCTAssertEqual(newSound.volume, 0.75, "Initial volume should be 0.75")
    XCTAssertFalse(newSound.isSelected, "Sound should not be selected initially")
    XCTAssertEqual(newSound.title, "Fresh Test", "Title should match initialization")
  }

  func testToggle() {
    XCTAssertFalse(sound.isSelected, "Should start unselected")
    sound.toggle()
    XCTAssertTrue(sound.isSelected, "Should be selected after toggle")
    sound.toggle()
    XCTAssertFalse(sound.isSelected, "Should be unselected after second toggle")
  }

  func testInvalidVolume() {
    let originalVolume = sound.volume

    sound.volume = 2.0  // Should fail silently and keep old value
    XCTAssertEqual(sound.volume, originalVolume, "Volume should not change when set above 1.0")

    sound.volume = -1.0  // Should fail silently and keep old value
    XCTAssertEqual(sound.volume, originalVolume, "Volume should not change when set below 0.0")

    sound.volume = 0.5  // Should work
    XCTAssertEqual(sound.volume, 0.5, "Volume should change for valid values")
  }
}
