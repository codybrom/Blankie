//
//  PresetEntryTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Pins how presets, Quick Mix, and the sound-editor preview hand playback to
//  each other. It checks that an application reports whether it ran, so callers
//  don't start the old mix. It also checks that leaving Quick Mix for a preset
//  drops the pre-Quick-Mix mix, a pending edit is saved before Quick Mix,
//  deleting the current preset while paused stays paused, a stale widget tile
//  leaves solo alone, and play/pause or a preset command ends a preview.
//
//  Engine-free (TestSounds), serialized and main-actor, on an isolated preset
//  list (SingletonSandbox).
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class PresetEntryTests {
  private let sandbox: SingletonSandbox
  private let originalStarredItems: [String]
  private var audioManager: AudioManager { sandbox.audioManager }
  private var presetManager: PresetManager { sandbox.presetManager }

  init() async {
    sandbox = await SingletonSandbox.make(
      soundNames: ["test-entry-a", "test-entry-b", "test-entry-preview"])
    originalStarredItems = GlobalSettings.shared.starredItems
  }

  isolated deinit {
    sandbox.restore()
    GlobalSettings.shared.setStarredItems(originalStarredItems)
  }

  // MARK: - Helpers

  /// Returns two sounds, with `a` selected.
  private func makeSounds() -> (a: TestSound, b: TestSound) {
    let a = TestSound(fileName: "test-entry-a")
    a.isSelected = true
    a.volume = 0.5
    let b = TestSound(fileName: "test-entry-b")
    audioManager.sounds = [a, b]
    return (a, b)
  }

  private func preset(_ name: String, selecting selected: Set<String>, from sounds: [Sound])
    -> Preset
  {
    PresetFactory.makePreset(
      name: name,
      soundStates: sounds.map {
        PresetState(fileName: $0.fileName, isSelected: selected.contains($0.fileName), volume: 0.5)
      },
      soundOrder: sounds.map(\.fileName))
  }

  /// Installs `presets`, makes the first current and fully applied.
  private func install(_ presets: [Preset]) async {
    presetManager.setPresets(presets)
    presetManager.setCurrentPreset(presets.first)
    presetManager.presetStatesApplied = true
    await sandbox.settle()
  }

  // MARK: - applyPreset reports whether it ran (F1)

  /// Callers start playback only when nothing was applied. An application starts
  /// the new mix itself, and playing first would start the old one.
  @Test func applyPresetReportsWhetherItApplied() async throws {
    let (a, b) = makeSounds()
    let first = preset("Entry One", selecting: [a.fileName], from: [a, b])
    let second = preset("Entry Two", selecting: [b.fileName], from: [a, b])
    await install([first, second])

    #expect(try presetManager.applyPreset(first) == false)
    #expect(try presetManager.applyPreset(second) == true)
    await sandbox.waitForPresetApply()
    #expect(b.isSelected)
    #expect(!a.isSelected)
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Quick Mix exits (F3)

  /// Leaving Quick Mix for a preset drops the pre-Quick-Mix mix and preset, so
  /// the preset about to apply isn't preceded by the old mix (or short-circuited
  /// when it's the same preset).
  @Test func leavingQuickMixForAPresetDropsTheOldMix() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM", selecting: [a.fileName], from: [a, b])
    await install([current])

    audioManager.enterQuickMix()
    audioManager.leaveTransientModes()

    #expect(!audioManager.isQuickMix)
    #expect(presetManager.currentPreset == nil)
    #expect(!a.isSelected)
    #expect(a.volume == 0.5)
  }

  /// The default exit (Quick Mix's own close) still restores the earlier mix.
  @Test func exitingQuickMixRestoresThePreset() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM Restore", selecting: [a.fileName], from: [a, b])
    await install([current])

    audioManager.enterQuickMix()
    audioManager.exitQuickMix()

    #expect(presetManager.currentPreset?.id == current.id)
    #expect(a.isSelected)
  }

  /// Entering Quick Mix saves the edit still waiting on the coalesced refresh.
  /// Quick Mix clears the current preset, so the refresh would skip it.
  @Test func enteringQuickMixSavesThePendingEdit() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM Flush", selecting: [a.fileName], from: [a, b])
    await install([current])

    a.volume = 0.3
    audioManager.enterQuickMix()

    let saved = presetManager.presets.first { $0.id == current.id }?
      .soundStates.first { $0.fileName == a.fileName }?.volume
    #expect(saved == 0.3)
    audioManager.exitQuickMix()
  }

  // MARK: - Deleting the current preset (D1)

  /// Deleting the current preset while paused makes the next one current
  /// without starting it.
  @Test func deletingTheCurrentPresetWhilePausedStaysPaused() async {
    let (a, b) = makeSounds()
    let doomed = preset("Entry Doomed", selecting: [a.fileName], from: [a, b])
    let next = preset("Entry Next", selecting: [b.fileName], from: [a, b])
    await install([doomed, next])
    #expect(!audioManager.isGloballyPlaying)

    presetManager.deletePreset(doomed)
    await sandbox.waitForPresetApply()

    #expect(presetManager.currentPreset?.id == next.id)
    #expect(!audioManager.isGloballyPlaying)
  }

  // MARK: - Stale widget tile (X2)

  /// A tile for a deleted preset throws before leaving solo, so the soloed
  /// sound isn't left paused under a "playing" state.
  @Test func staleWidgetTileLeavesSoloAlone() async {
    let (a, b) = makeSounds()
    await install([preset("Entry Solo", selecting: [a.fileName], from: [a, b])])
    audioManager.enterSoloMode(for: b, startPlaying: false)

    let intent = WidgetPlayFavoriteIntent(favoriteToken: UUID().uuidString)
    await #expect(throws: BlankieIntentError.self) { _ = try await intent.perform() }

    #expect(audioManager.soloModeSound === b)
    audioManager.exitSoloModeWithoutResuming()
  }

  // MARK: - Commands end a preview (F2)

  /// Play/pause from anywhere ends the sound-editor preview first.
  @Test func playbackCommandEndsThePreview() async {
    _ = makeSounds()
    audioManager.previewModeSound = TestSound(fileName: "test-entry-preview")

    audioManager.setGlobalPlaybackState(false)

    #expect(audioManager.previewModeSound == nil)
  }

  /// Applying a preset ends the preview before the new mix goes in.
  @Test func presetCommandEndsThePreview() async throws {
    let (a, b) = makeSounds()
    let first = preset("Entry Preview One", selecting: [a.fileName], from: [a, b])
    let second = preset("Entry Preview Two", selecting: [b.fileName], from: [a, b])
    await install([first, second])
    audioManager.previewModeSound = TestSound(fileName: "test-entry-preview")

    try presetManager.applyPreset(second)
    #expect(audioManager.previewModeSound == nil)
    await sandbox.waitForPresetApply()
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Interruption resume (F4)

  #if os(iOS) || os(visionOS)
    /// A play during an interruption supersedes it, so its end can't resume
    /// playback over a pause made after that play.
    @Test func playDuringInterruptionClearsTheResume() async {
      _ = makeSounds()
      audioManager.wasPlayingWhenInterrupted = true

      audioManager.setGlobalPlaybackState(true)
      #expect(!audioManager.wasPlayingWhenInterrupted)
      audioManager.setGlobalPlaybackState(false)
    }
  #endif
}
