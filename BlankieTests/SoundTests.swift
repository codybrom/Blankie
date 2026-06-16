//
//  SoundTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import Foundation
import Testing

@testable import Blankie

/// A Sound whose loadSound() never touches the filesystem or audio session.
private final class MockSound: Sound {
  init(title: String, systemIconName: String, fileName: String, fileExtension: String = "mp3") {
    super.init(
      title: title, systemIconName: systemIconName, fileName: fileName, fileExtension: fileExtension
    )
  }

  override func loadSound() {
    player = nil
  }
}

@Suite @MainActor
struct SoundTests {
  // A fresh sound per test (the suite is re-instantiated for each `@Test`).
  private let sound = MockSound(
    title: "Test Sound", systemIconName: "speaker.wave", fileName: "test")

  @Test func initialState() {
    let newSound = MockSound(title: "Fresh Test", systemIconName: "speaker.wave", fileName: "test")
    #expect(newSound.volume == 0.75, "Initial volume should be 0.75")
    #expect(!newSound.isSelected, "Sound should not be selected initially")
    #expect(newSound.title == "Fresh Test", "Title should match initialization")
  }

  @Test func toggle() {
    #expect(!sound.isSelected, "Should start unselected")
    sound.toggle()
    #expect(sound.isSelected, "Should be selected after toggle")
    sound.toggle()
    #expect(!sound.isSelected, "Should be unselected after second toggle")
  }

  @Test func invalidVolume() {
    let originalVolume = sound.volume

    sound.volume = 2.0  // Should fail silently and keep old value
    #expect(sound.volume == originalVolume, "Volume should not change when set above 1.0")

    sound.volume = -1.0  // Should fail silently and keep old value
    #expect(sound.volume == originalVolume, "Volume should not change when set below 0.0")

    sound.volume = 0.5  // Should work
    #expect(sound.volume == 0.5, "Volume should change for valid values")
  }
}
