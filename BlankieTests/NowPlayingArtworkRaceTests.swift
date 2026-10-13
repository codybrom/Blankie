//
//  NowPlayingArtworkRaceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Pins the ways lock screen artwork fell out of step with the preset. A preset
//  with no animation kept the previous loop, a forced refresh dropped the
//  preset's own still, a failed still read was never retried, and a finished
//  download never reached the 26 card.
//
//  The 26 (MediaPlayer) cases call the backend's artwork steps directly and
//  never publish, so they are safe next to the 27 backend. The one that does
//  publish runs below OS 27 only.
//
//  Serialized and main-actor because it drives the PresetManager and
//  GlobalSettings singletons. Every touched value is restored in deinit.
//

import Foundation
import MediaPlayer
import Testing

@testable import Blankie

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

  // MARK: - Preset without animation (N3)

  #if os(iOS)
    /// N3 on 26: switching to a preset with no animation (and no app-wide
    /// default) clears the previous preset's loop instead of keeping it.
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
    /// N3 on 27: the same switch through the MediaSession backend.
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
  #endif

  // MARK: - Forced refresh of the same preset (N7)

  /// N7 on 26: a forced refresh of a preset whose stored still is already
  /// showing keeps that still. It used to fall through to the fallback.
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

  /// On 26, a still that fails to load leaves its id unrecorded, so the next
  /// update reads it again instead of treating it as already showing.
  @Test func failedStillReadLeavesTheIdUnrecorded() async {
    let backend = NowPlayingManager()
    var preset = makePresetWithoutAnimation()
    preset.artworkId = UUID()  // nothing stored under this id

    await backend.loadStaticArtworkSync(from: preset, fallbackArtworkId: nil)

    #expect(backend.currentArtworkId == nil)
  }

  // MARK: - Finished download (N5)

  #if os(iOS)
    /// N5 on 26: a finished animation download has to rebuild artwork on the
    /// next publish even though the preset didn't change. Incremental
    /// publishes never carry artwork keys. Publishes through
    /// MPNowPlayingInfoCenter, so it runs below OS 27 only.
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
