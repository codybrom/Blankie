//
//  PresetManagerCleanupTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The decision core behind cleanupDeletedCustomSounds. Pruning is irreversible, so a failed
//  custom-sound store open must skip it.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PresetManagerCleanupTests {

  private func state(_ fileName: String) -> PresetState {
    PresetState(fileName: fileName, isSelected: true, volume: 0.5)
  }

  /// No custom rows while a preset references an unknown custom reads as a transient load failure.
  @Test func skipsWhenCustomsMissingButReferenced() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("my-custom")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: [])
    #expect(decision == .skipTransient)
  }

  /// A state in neither the loaded sounds nor the rows is deleted.
  @Test func removesTrulyDeletedStates() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("ghost")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: ["other-custom"])
    #expect(decision == .filtered([[state("rain")]]))
  }

  /// The valid set is the loaded sounds plus the SwiftData rows.
  @Test func keepsRowsThatExistButFailedToLoad() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("custom-x")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: ["custom-x"])
    #expect(decision == .filtered([[state("rain"), state("custom-x")]]))
  }

  @Test func emptyCustomsWithNoReferencesIsNotTransient() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: [])
    #expect(decision == .filtered([[state("rain")]]))
  }
}
