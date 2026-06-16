//
//  PresetManagerCleanupTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The pure decision core behind cleanupDeletedCustomSounds. The transient-load
//  guard here is the only thing standing between a failed custom-sound store open
//  and irreversibly stripping every custom-sound state from every preset.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PresetManagerCleanupTests {

  private func state(_ fileName: String) -> PresetState {
    PresetState(fileName: fileName, isSelected: true, volume: 0.5)
  }

  /// No custom rows visible but a preset references an unknown custom → assume a
  /// transient load failure and keep everything (never strip irreversibly).
  @Test func skipsWhenCustomsMissingButReferenced() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("my-custom")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: [])
    #expect(decision == .skipTransient)
  }

  /// With custom rows present, a state in NEITHER loaded sounds nor rows is a
  /// genuinely deleted sound and is removed; the rest are kept.
  @Test func removesTrulyDeletedStates() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("ghost")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: ["other-custom"])
    #expect(decision == .filtered([[state("rain")]]))
  }

  /// A row that exists but failed to load as a Sound this launch is KEPT — the
  /// valid set is loaded sounds UNION the SwiftData rows.
  @Test func keepsRowsThatExistButFailedToLoad() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain"), state("custom-x")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: ["custom-x"])
    #expect(decision == .filtered([[state("rain"), state("custom-x")]]))
  }

  /// Empty customs AND nothing references a custom → not transient, just a
  /// no-op filter.
  @Test func emptyCustomsWithNoReferencesIsNotTransient() {
    let decision = PresetManager.customSoundCleanupDecision(
      presetStates: [[state("rain")]],
      loadedSoundFileNames: ["rain"],
      customRowFileNames: [])
    #expect(decision == .filtered([[state("rain")]]))
  }
}
