//
//  NowPlayingArtworkRaceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Lock screen artwork follows the preset across loops, stills, fallbacks and downloads.
//  The 26 cases call artwork steps without publishing, except one that runs below OS 27.
//  Serialized: deinit restores the PresetManager and GlobalSettings values it touches.
//

import Foundation
import MediaPlayer
import Testing

@testable import Blankie

#if os(iOS)
  import UIKit
#endif

@Suite(.serialized) @MainActor final class NowPlayingArtworkRaceTests {
  private let originalCurrentPreset: Preset?
  private let originalDefaultArtwork: AnimatedArtworkRef?
  private let originalBackgroundEnabled: Bool

  init() {
    originalCurrentPreset = PresetManager.shared.currentPreset
    originalDefaultArtwork = GlobalSettings.shared.defaultLockScreenArtwork
    originalBackgroundEnabled = GlobalSettings.shared.lockScreenBackgroundEnabled
    // No app-wide animation, so a preset without its own has none at all.
    GlobalSettings.shared.setDefaultLockScreenArtwork(nil)
    GlobalSettings.shared.setLockScreenBackgroundEnabled(true)
  }

  isolated deinit {
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
    GlobalSettings.shared.setDefaultLockScreenArtwork(originalDefaultArtwork)
    GlobalSettings.shared.setLockScreenBackgroundEnabled(originalBackgroundEnabled)
  }

  private func makePresetWithoutAnimation() -> Preset {
    var preset = PresetFactory.makePreset(accentColorName: "blue")
    preset.artworkId = nil
    preset.animatedArtwork = nil
    preset.staticArtworkPath = nil
    return preset
  }

  // MARK: - Preset without animation

  #if os(iOS)
    @Test func mediaPlayerPresetWithoutAnimationClearsTheLoop() {
      let backend = NowPlayingManager()
      backend.currentAnimatedLoopPath = "previous-preset-loop"
      backend.nowPlayingInfo[AnimatedArtworkKey.square.rawValue] = "previous loop"

      backend.updateAnimatedArtwork(for: makePresetWithoutAnimation())

      #expect(backend.currentAnimatedLoopPath == nil)
      #expect(backend.nowPlayingInfo[AnimatedArtworkKey.square.rawValue] == nil)
    }
  #endif

  #if canImport(NowPlaying) && os(iOS)
    @Test func mediaSessionPresetWithoutAnimationClearsTheLoop() throws {
      guard #available(iOS 27, *) else { return }
      guard NowPlayingDisplay.shouldPublishAnimatedArtwork() else {
        try Test.cancel("Reduce Motion or Low Power Mode turns animated artwork off here")
      }
      let backend = MediaSessionNowPlaying()
      backend.currentAnimatedLoopPath = "previous-preset-loop"
      let preset = makePresetWithoutAnimation()
      PresetManager.shared.setCurrentPreset(preset)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()

      #expect(backend.currentAnimatedLoopPath == nil)
      #expect(backend.model.animatedArtwork == nil)
    }

    @Test func mediaSessionPresetWithAnUnavailableLoopClearsTheOldOne() throws {
      guard #available(iOS 27, *) else { return }
      guard NowPlayingDisplay.shouldPublishAnimatedArtwork() else {
        try Test.cancel("Reduce Motion or Low Power Mode turns animated artwork off here")
      }
      // A playable custom loop: any file stands in for the video, but the
      // preview has to decode.
      let loopPath = AnimatedArtworkFileStore.makeRelativeLoopPath(for: UUID())
      let previewPath = AnimatedArtworkFileStore.makeRelativePreviewPath(
        for: UUID(), fileExtension: "jpg")
      let preview = try #require(
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
          .image { _ in }.jpegData(compressionQuality: 0.9))
      _ = try AnimatedArtworkFileStore.writeData(Data([0]), to: loopPath)
      _ = try AnimatedArtworkFileStore.writeData(preview, to: previewPath)
      defer {
        AnimatedArtworkFileStore.removeItemIfExists(relativePath: loopPath)
        AnimatedArtworkFileStore.removeItemIfExists(relativePath: previewPath)
      }
      let backend = MediaSessionNowPlaying()

      var playable = makePresetWithoutAnimation()
      playable.animatedArtwork = AnimatedArtworkRef(
        source: .custom, loopPath: loopPath, previewPath: previewPath)
      PresetManager.shared.setCurrentPreset(playable)
      backend.updateInfo(preset: playable, presetName: playable.name, isPlaying: false)
      backend.flushPendingPublish()
      try #require(backend.model.animatedArtwork != nil)

      var pending = makePresetWithoutAnimation()
      pending.animatedArtwork = AnimatedArtworkRef(
        source: .custom, loopPath: "test-missing-\(UUID().uuidString).mov")
      PresetManager.shared.setCurrentPreset(pending)
      backend.updateInfo(preset: pending, presetName: pending.name, isPlaying: false)
      backend.flushPendingPublish()

      #expect(backend.currentAnimatedLoopPath == nil)
      #expect(backend.model.animatedArtwork == nil)
    }
  #endif

  // MARK: - Forced refresh of the same preset

  @Test func forcedRefreshOfTheSamePresetKeepsItsStill() async {
    let backend = NowPlayingManager()
    let artworkId = UUID()
    var preset = makePresetWithoutAnimation()
    preset.artworkId = artworkId
    backend.currentArtworkId = artworkId
    backend.nowPlayingInfo[MPMediaItemPropertyArtwork] = "this preset's still"

    await backend.loadStaticArtworkSync(from: preset, fallbackArtworkId: artworkId)

    #expect(backend.currentArtworkId == artworkId)
    #expect(backend.nowPlayingInfo[MPMediaItemPropertyArtwork] as? String == "this preset's still")
  }

  /// The next update then reads the still again.
  @Test func failedStillReadLeavesTheIdUnrecorded() async {
    let backend = NowPlayingManager()
    var preset = makePresetWithoutAnimation()
    preset.artworkId = UUID()  // nothing stored under this id

    await backend.loadStaticArtworkSync(from: preset, fallbackArtworkId: nil)

    #expect(backend.currentArtworkId == nil)
  }

  /// A new preset's first publish can draw the fallback before its sounds are selected.
  @Test func fallbackRedrawsWhenTheSelectionLandsLater() {
    let originalSounds = AudioManager.shared.sounds
    let sound = TestSound(fileName: "test-fallback-redraw")
    defer {
      AudioManager.shared.sounds = originalSounds
      UserDefaults.shared.removeObject(forKey: "\(sound.fileName)_isSelected")
    }
    AudioManager.shared.sounds = [sound]
    PresetManager.shared.setCurrentPreset(makePresetWithoutAnimation())
    let backend = NowPlayingManager()

    backend.updateArtwork(artworkData: nil)
    #expect(backend.shownFallbackGlyph == .brand)

    sound.isSelected = true
    #expect(backend.redrawFallbackIfStale())
    #expect(backend.shownFallbackGlyph == .composite([sound.systemIconName]))
    #expect(!backend.redrawFallbackIfStale(), "an up-to-date fallback isn't redrawn")
  }

  // MARK: - Finished download

  #if os(iOS)
    /// Incremental publishes carry no artwork keys. Publishes through MPNowPlayingInfoCenter,
    /// so it runs below OS 27 only.
    @Test func finishedDownloadRebuildsArtworkForTheSamePreset() async {
      if #available(iOS 27, *) { return }
      AudioEngineManager.shared.pause()  // a running engine holds paused publishes
      let backend = NowPlayingManager()
      let preset = makePresetWithoutAnimation()
      PresetManager.shared.setCurrentPreset(preset)
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      await spinMainLoop(timeout: 0.3)

      backend.animatedArtworkDidDownload()
      #expect(backend.needsArtworkRebuild)
      await spinMainLoop(timeout: 0.5) { !backend.needsArtworkRebuild }

      #expect(!backend.needsArtworkRebuild, "the republish rebuilds the artwork in full")
      backend.clear()
    }
  #endif
}
