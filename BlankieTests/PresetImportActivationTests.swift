//
//  PresetImportActivationTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/13/26.
//
//  An import leaves single sound and Quick Mix, activates the imported preset and clamps an
//  archive's volume adjustments. Runs on an in-memory store and isolated presets
//  (SingletonSandbox).
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class PresetImportActivationTests {
  private let sandbox: SingletonSandbox
  nonisolated private static let names = ["test-activate-a", "test-activate-b"]

  init() async throws {
    sandbox = await SingletonSandbox.make(soundNames: Self.names)
    _ = try sandbox.installInMemoryStore()
    sandbox.audioManager.sounds = Self.names.map { TestSound(fileName: $0) }
  }

  isolated deinit {
    for name in Self.names { SoundCustomizationManager.shared.removeCustomization(for: name) }
    sandbox.restore()
  }

  /// Imports a preset over the first sound, unselected so nothing plays.
  private func importPreset(customizations: [SoundCustomization] = []) async throws -> Preset {
    let preset = PresetFactory.makePreset(
      name: "Imported",
      soundStates: [PresetState(fileName: Self.names[0], isSelected: false, volume: 0.5)],
      soundOrder: [Self.names[0]])
    let archive = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: archive) }
    try ArchiveSupport.writeValidArchiveDir(at: archive, preset: preset)
    if !customizations.isEmpty {
      let soundsDir = archive.appendingPathComponent(PresetArchive.soundsDirectoryName)
      try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
      try JSONEncoder().encode(
        SoundsManifest(customSounds: [], builtInCustomizations: customizations)
      ).write(to: soundsDir.appendingPathComponent(PresetArchive.soundsMetadataFileName))
    }

    let imported = try await PresetImporter.shared.importArchive(from: archive)
    await sandbox.waitForPresetApply()
    return imported
  }

  @Test func importLeavesSingleForTheImportedPreset() async throws {
    sandbox.audioManager.enterSingleSound(for: sandbox.audioManager.sounds[1], startPlaying: false)

    let imported = try await importPreset()

    #expect(sandbox.audioManager.singleSound == nil)
    #expect(sandbox.presetManager.currentPreset?.id == imported.id)
  }

  @Test func importLeavesQuickMixForTheImportedPreset() async throws {
    sandbox.audioManager.enterQuickMix()

    let imported = try await importPreset()

    #expect(!sandbox.audioManager.isQuickMix)
    #expect(sandbox.presetManager.currentPreset?.id == imported.id)
  }

  /// An archive can carry any value, so adjustments clamp to the editor's 0.5
  /// to 8 range.
  @Test func importClampsVolumeAdjustments() async throws {
    _ = try await importPreset(customizations: [
      SoundCustomization(fileName: Self.names[0], volumeAdjustment: 0.1),
      SoundCustomization(fileName: Self.names[1], volumeAdjustment: 100),
    ])

    let manager = SoundCustomizationManager.shared
    #expect(manager.getCustomization(for: Self.names[0])?.volumeAdjustment == 0.5)
    #expect(manager.getCustomization(for: Self.names[1])?.volumeAdjustment == 8)
  }
}
