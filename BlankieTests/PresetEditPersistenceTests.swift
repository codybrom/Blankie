//
//  PresetEditPersistenceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Mix edits reach the current preset through a 100 ms coalesced refresh, which single sound,
//  preview and an unapplied preset switch off. Edits survive a mode or preset change inside that
//  window, and leaving single sound switches saving back on. Engine-free, on SingletonSandbox.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class PresetEditPersistenceTests {
  private let sandbox: SingletonSandbox
  private var audioManager: AudioManager { sandbox.audioManager }
  private var presetManager: PresetManager { sandbox.presetManager }

  init() async {
    sandbox = await SingletonSandbox.make(
      soundNames: ["test-edit-a", "test-edit-b", "test-edit-single"])
  }

  isolated deinit {
    sandbox.restore()
  }

  // MARK: - Helpers

  /// Installs `presets`, makes the first one current and fully applied, then lets
  /// the setup's own coalesced refresh land.
  private func install(_ presets: [Preset]) async {
    presetManager.setPresets(presets)
    presetManager.setCurrentPreset(presets.first)
    presetManager.presetStatesApplied = true
    await sandbox.settle()
  }

  private func savedVolume(of fileName: String, in presetID: UUID) -> Float? {
    presetManager.presets.first { $0.id == presetID }?
      .soundStates.first { $0.fileName == fileName }?.volume
  }

  private func persistedVolume(of fileName: String, in presetID: UUID) -> Float? {
    PresetStorage.loadCustomPresets().first { $0.id == presetID }?
      .soundStates.first { $0.fileName == fileName }?.volume
  }

  private func makeMix() -> (edited: TestSound, other: TestSound) {
    let edited = TestSound(fileName: "test-edit-a")
    edited.isSelected = true
    edited.volume = 0.5
    let other = TestSound(fileName: "test-edit-single")
    audioManager.sounds = [edited, other]
    return (edited, other)
  }

  private func preset(for sounds: [Sound], name: String = "Edit Target") -> Preset {
    PresetFactory.makePreset(
      name: name, soundStates: sounds.map { $0.captureState() },
      soundOrder: sounds.map(\.fileName))
  }

  // MARK: - Pending edit inside the coalescing window

  /// Single sound turns the refresh off, so entering it saves the pending edit first.
  @Test func editJustBeforeSingleIsSaved() async {
    let (edited, single) = makeMix()
    let target = preset(for: [edited, single])
    await install([target])

    edited.volume = 0.3
    audioManager.enterSingleSound(for: single, startPlaying: false)

    #expect(savedVolume(of: edited.fileName, in: target.id) == 0.3)
    await sandbox.settle()
    #expect(persistedVolume(of: edited.fileName, in: target.id) == 0.3)
  }

  /// Entering preview saves the pending edit for the same reason.
  @Test func editJustBeforePreviewIsSaved() async {
    let (edited, previewed) = makeMix()
    let target = preset(for: [edited, previewed])
    await install([target])

    edited.volume = 0.3
    audioManager.enterPreviewMode(for: previewed)

    #expect(savedVolume(of: edited.fileName, in: target.id) == 0.3)
    audioManager.exitPreviewMode()
    await sandbox.settle()
    #expect(persistedVolume(of: edited.fileName, in: target.id) == 0.3)
  }

  /// After a switch the refresh targets the incoming preset, so the pending edit is saved into
  /// the outgoing one first.
  @Test func editJustBeforePresetSwitchStaysWithTheOutgoingPreset() async throws {
    let (edited, other) = makeMix()
    let outgoing = preset(for: [edited, other], name: "Outgoing")
    let incoming = PresetFactory.makePreset(
      name: "Incoming",
      soundStates: [PresetState(fileName: other.fileName, isSelected: false, volume: 0.7)],
      soundOrder: [other.fileName])
    await install([outgoing, incoming])

    edited.volume = 0.3
    try presetManager.applyPreset(incoming, autoPlay: false)

    #expect(savedVolume(of: edited.fileName, in: outgoing.id) == 0.3)
    await sandbox.waitForPresetApply()
    #expect(persistedVolume(of: edited.fileName, in: outgoing.id) == 0.3)
    #expect(savedVolume(of: edited.fileName, in: incoming.id) == nil)
  }

  // MARK: - Leaving single sound without resuming

  /// A relaunch into single sound skips the preset's apply, so saving stays off. Leaving single
  /// sound the way Siri, widgets and CarPlay do must re-sync and switch saving back on.
  @Test func leavingSingleWithoutResumingTurnsSavingBackOn() async {
    let (edited, single) = makeMix()
    let target = preset(for: [edited, single])
    await install([target])
    presetManager.presetStatesApplied = false  // as after a relaunch into single sound
    audioManager.enterSingleSound(for: single, startPlaying: false)

    audioManager.leaveTransientModes()
    #expect(audioManager.singleSound == nil)
    #expect(presetManager.presetStatesApplied)

    edited.volume = 0.25
    await sandbox.waitUntil { persistedVolume(of: edited.fileName, in: target.id) == 0.25 }
    #expect(savedVolume(of: edited.fileName, in: target.id) == 0.25)
    #expect(persistedVolume(of: edited.fileName, in: target.id) == 0.25)
  }
}
