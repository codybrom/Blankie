//
//  WidgetTokenGrammarTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 7/8/26.
//
//  The persisted token grammar wiring favorites to widgets, Control Center,
//  Siri, and CarPlay. A `starredItems` token is one of four mutually exclusive
//  shapes (allSounds | quickMix | solo:<fileName> | preset-UUID); this pins the
//  codec, the token→display resolution, and the active-token precedence so a
//  format or precedence change can't silently break those surfaces.
//
//  The resolution suite is serialized + main-actor: it drives the shared
//  AudioManager / PresetManager singletons and restores every touched field.
//

import Foundation
import Testing

@testable import Blankie

// MARK: - Pure token codec

@Suite struct WidgetTokenGrammarTests {

  @Test func soloTokenRoundTrips() {
    let token = GlobalSettings.soloToken(forFileName: "rain")
    #expect(token == "solo:rain")
    #expect(GlobalSettings.soloFileName(fromToken: token) == "rain")
  }

  /// Only a solo token decodes to a file name; the other three shapes don't.
  @Test func soloFileNameRejectsNonSoloTokens() {
    #expect(GlobalSettings.soloFileName(fromToken: GlobalSettings.allSoundsToken) == nil)
    #expect(GlobalSettings.soloFileName(fromToken: GlobalSettings.quickMixToken) == nil)
    #expect(GlobalSettings.soloFileName(fromToken: UUID().uuidString) == nil)
    #expect(GlobalSettings.soloFileName(fromToken: "") == nil)
  }

  /// A file name containing the prefix delimiter survives the round-trip: only
  /// the first `solo:` is stripped, so the rest is returned intact.
  @Test func soloTokenPreservesColonInFileName() {
    let token = GlobalSettings.soloToken(forFileName: "a:b")
    #expect(token == "solo:a:b")
    #expect(GlobalSettings.soloFileName(fromToken: token) == "a:b")
  }

  /// The four shapes are mutually exclusive: neither special token carries the
  /// solo prefix, and only a preset UUID string parses as a UUID.
  @Test func tokenShapesAreMutuallyExclusive() {
    #expect(!GlobalSettings.allSoundsToken.hasPrefix(GlobalSettings.soloTokenPrefix))
    #expect(!GlobalSettings.quickMixToken.hasPrefix(GlobalSettings.soloTokenPrefix))
    #expect(UUID(uuidString: GlobalSettings.allSoundsToken) == nil)
    #expect(UUID(uuidString: GlobalSettings.quickMixToken) == nil)
    #expect(UUID(uuidString: GlobalSettings.soloToken(forFileName: "rain")) == nil)
    let uuid = UUID()
    #expect(UUID(uuidString: uuid.uuidString) == uuid)
  }
}

// MARK: - Token → display resolution + active-token precedence

@Suite(.serialized) @MainActor final class WidgetFavoriteResolutionTests {
  private let audioManager = AudioManager.shared
  private let originalSounds: [Sound]
  private let originalPresets: [Preset]
  private let originalCurrentPreset: Preset?
  private let originalSolo: Sound?
  private let originalQuickMix: Bool

  init() {
    originalSounds = audioManager.sounds
    originalPresets = PresetManager.shared.presets
    originalCurrentPreset = PresetManager.shared.currentPreset
    originalSolo = audioManager.soloModeSound
    originalQuickMix = audioManager.isQuickMix
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
  }

  isolated deinit {
    audioManager.soloModeSound = originalSolo
    audioManager.isQuickMix = originalQuickMix
    audioManager.sounds = originalSounds
    PresetManager.shared.setPresets(originalPresets)
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
  }

  // MARK: widgetFavorite(forToken:)

  @Test func resolvesAllSoundsToken() {
    let favorite = audioManager.widgetFavorite(forToken: GlobalSettings.allSoundsToken)
    #expect(favorite?.token == GlobalSettings.allSoundsToken)
    #expect(favorite?.displayName == String(localized: "All Blankie Sounds"))
    #expect(favorite?.systemIconName == "square.grid.2x2")
    #expect(favorite?.thumbnailKey == nil)
    #expect(favorite?.subtitle == nil)
  }

  @Test func resolvesQuickMixToken() {
    let favorite = audioManager.widgetFavorite(forToken: GlobalSettings.quickMixToken)
    #expect(favorite?.token == GlobalSettings.quickMixToken)
    #expect(favorite?.displayName == String(localized: "Quick Mix"))
    #expect(favorite?.systemIconName == "shuffle")
    #expect(favorite?.thumbnailKey == nil)
  }

  @Test func resolvesSoloTokenToItsSound() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    let token = GlobalSettings.soloToken(forFileName: "test-rain")

    let favorite = audioManager.widgetFavorite(forToken: token)
    #expect(favorite?.token == token)
    #expect(favorite?.displayName == rain.localizedTitle)
    #expect(favorite?.systemIconName == rain.systemIconName)
    #expect(favorite?.thumbnailKey == nil)
  }

  @Test func soloTokenForMissingSoundIsNil() {
    audioManager.sounds = []
    let token = GlobalSettings.soloToken(forFileName: "ghost")
    #expect(audioManager.widgetFavorite(forToken: token) == nil)
  }

  @Test func resolvesPresetUUIDToken() {
    let preset = PresetFactory.makePreset(
      name: "Widget Preset", soundStates: [], soundOrder: [], creatorName: nil)
    PresetManager.shared.setPresets([preset])

    let favorite = audioManager.widgetFavorite(forToken: preset.id.uuidString)
    #expect(favorite?.token == preset.id.uuidString)
    #expect(favorite?.displayName == preset.displayName)
    #expect(favorite?.systemIconName == "square.stack.3d.up.fill")
    #expect(favorite?.thumbnailKey == "preset_thumb_\(preset.id.uuidString)")
  }

  @Test func unknownUUIDTokenIsNil() {
    PresetManager.shared.setPresets([])
    #expect(audioManager.widgetFavorite(forToken: UUID().uuidString) == nil)
  }

  // MARK: presetSubtitle(for:)

  @Test func presetSubtitleCreatorWinsOverSounds() {
    audioManager.sounds = [TestSound(fileName: "test-rain")]
    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: "test-rain", isSelected: true, volume: 0.5)],
      soundOrder: ["test-rain"], creatorName: "Ada")
    #expect(audioManager.presetSubtitle(for: preset) == "Ada")
  }

  @Test func presetSubtitleJoinsSelectedTitlesUnderBudget() {
    audioManager.sounds = [TestSound(fileName: "test-rain"), TestSound(fileName: "test-waves")]
    let preset = PresetFactory.makePreset(
      soundStates: [
        PresetState(fileName: "test-rain", isSelected: true, volume: 0.5),
        PresetState(fileName: "test-waves", isSelected: false, volume: 0.5),
      ],
      soundOrder: ["test-rain", "test-waves"], creatorName: nil)
    // Only the selected sound contributes; the deselected one is excluded.
    #expect(audioManager.presetSubtitle(for: preset) == "test-rain")
  }

  @Test func presetSubtitleOverBudgetFallsBackToCount() {
    let names = ["aurora-borealis", "distant-thunder", "gentle-rainfall", "ocean-currents"]
    audioManager.sounds = names.map { TestSound(fileName: $0) }
    let preset = PresetFactory.makePreset(
      soundStates: names.map { PresetState(fileName: $0, isSelected: true, volume: 0.5) },
      soundOrder: names, creatorName: nil)
    #expect(audioManager.presetSubtitle(for: preset) == String(localized: "\(names.count) sounds"))
  }

  @Test func presetSubtitleSingleLongTitleReturnedInFull() {
    let long = "test-" + String(repeating: "x", count: 60)
    audioManager.sounds = [TestSound(fileName: long)]
    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: long, isSelected: true, volume: 0.5)],
      soundOrder: [long], creatorName: nil)
    #expect(audioManager.presetSubtitle(for: preset) == long)
  }

  @Test func presetSubtitleNothingSelectedIsNil() {
    audioManager.sounds = [TestSound(fileName: "test-rain")]
    let preset = PresetFactory.makePreset(
      soundStates: [PresetState(fileName: "test-rain", isSelected: false, volume: 0.5)],
      soundOrder: ["test-rain"], creatorName: nil)
    #expect(audioManager.presetSubtitle(for: preset) == nil)
  }

  // MARK: currentFavoriteToken precedence

  /// Solo outranks Quick Mix and a current preset. Set the mode state directly
  /// (the engine-free convention `PresetApplyStatesTests` uses) so the read
  /// under test has no audio/session/media-remote side effects.
  @Test func currentTokenPrefersSolo() {
    let rain = TestSound(fileName: "test-rain")
    audioManager.sounds = [rain]
    let preset = PresetFactory.makePreset(isDefault: false)
    PresetManager.shared.setPresets([preset])
    PresetManager.shared.setCurrentPreset(preset)
    audioManager.isQuickMix = true
    audioManager.soloModeSound = rain

    #expect(audioManager.currentFavoriteToken == GlobalSettings.soloToken(forFileName: "test-rain"))
  }

  @Test func currentTokenIsQuickMixWithoutSolo() {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = true
    #expect(audioManager.currentFavoriteToken == GlobalSettings.quickMixToken)
  }

  @Test func currentTokenIsPresetUUID() {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    let preset = PresetFactory.makePreset(isDefault: false)
    PresetManager.shared.setPresets([preset])
    PresetManager.shared.setCurrentPreset(preset)
    #expect(audioManager.currentFavoriteToken == preset.id.uuidString)
  }

  @Test func currentTokenForDefaultPresetIsAllSounds() {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    let preset = PresetFactory.makePreset(isDefault: true)
    PresetManager.shared.setPresets([preset])
    PresetManager.shared.setCurrentPreset(preset)
    #expect(audioManager.currentFavoriteToken == GlobalSettings.allSoundsToken)
  }

  @Test func currentTokenIsNilWhenNothingActive() {
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    PresetManager.shared.setCurrentPreset(nil)
    #expect(audioManager.currentFavoriteToken == nil)
  }
}
