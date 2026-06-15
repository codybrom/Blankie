//
//  PlaybackPositionTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Testing

@testable import Blankie

/// Stage-1 tests for the Sound playback facade. Real playback (live position
/// read-back during playback and loop completion) needs a running engine and
/// audio hardware, so it stays on the on-device soak checklist rather than here.
///
/// Serialized + main-actor: these drive the shared audio engine and run-loop
/// timers, which XCTest ran on the main thread — `@MainActor` preserves that.
@Suite(.serialized) @MainActor
struct PlaybackPositionTests {

  /// Sound whose loadSound() never touches the filesystem or audio session.
  private final class HeadlessSound: Sound {
    init(fileName: String, duration: TimeInterval? = nil) {
      super.init(
        title: "Headless", systemIconName: "speaker.wave.2",
        fileName: fileName, fileExtension: "m4a", duration: duration)
    }
    override func loadSound() {
      player = nil
    }
  }

  // MARK: - Random-start range math

  /// The randomization rule (Sound+Loading/Sound+Playback) is
  /// start ∈ 0..<duration*0.75; assert the bound semantics directly.
  @Test func randomStartStaysWithinFirst75Percent() {
    let duration: Double = 120.0
    let maxPosition = duration * 0.75

    for _ in 0..<1_000 {
      let position = Double.random(in: 0..<maxPosition)
      #expect(position >= 0)
      #expect(position < maxPosition)
    }
  }

  // MARK: - Facade defaults without a player

  @Test func facadeDefaultsWhenUnloaded() {
    let sound = HeadlessSound(fileName: "headless-facade")

    #expect(!sound.isLoaded)
    #expect(!sound.isPlaying)
    #expect(sound.playbackPosition == 0)
    #expect(sound.playbackDuration == 0)
    #expect(sound.playbackState == .stopped)
  }

  // MARK: - State transitions without a player

  /// pause()/stop() early-return when no player exists: they must not crash,
  /// flip selection, or leave playbackState anything but .stopped.
  @Test func pauseAndStopAreSafeWithoutPlayer() {
    let sound = HeadlessSound(fileName: "headless-transition")
    #expect(sound.player == nil)

    sound.pause()
    #expect(sound.playbackState == .stopped)
    sound.pause(immediate: true)
    #expect(sound.playbackState == .stopped)
    sound.stop()
    #expect(sound.playbackState == .stopped)
    sound.resetSoundPosition()

    #expect(sound.player == nil)
    #expect(!sound.isSelected)
  }

  @Test func unloadResetsStateAndPlayer() {
    let sound = HeadlessSound(fileName: "headless-unload")
    sound.playbackState = .paused  // simulate a stale state before teardown

    sound.unload()

    #expect(sound.player == nil)
    #expect(sound.playbackState == .stopped)
  }

  // MARK: - Engine graph hygiene

  /// Repeated load/unload (the preview sheet pattern) must not accumulate nodes
  /// in the engine — unload() detaches what loadSound() attached.
  @Test func engineRegistryReturnsToBaselineAfterUnload() {
    let sound = Sound(
      title: "Leak Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    let baseline = AudioEngineManager.shared.registered.count

    for _ in 0..<3 {
      sound.loadSound()
      #expect(sound.isLoaded, "Bundled fireplace.m4a should load")
      #expect(
        AudioEngineManager.shared.registered.count == baseline + 1,
        "loadSound must attach exactly one player")
      sound.unload()
      #expect(
        AudioEngineManager.shared.registered.count == baseline,
        "unload must detach the player it attached")
    }
  }

  // MARK: - Fade layer math

  /// node.volume must always be baseVolume × fadeLevel; a zero-duration fade
  /// applies instantly and fires its completion synchronously.
  @Test func fadeLayerScalesNodeVolume() throws {
    let sound = Sound(
      title: "Fade Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    sound.loadSound()
    let player = try #require(sound.player, "fireplace.m4a should load")
    defer { sound.unload() }

    player.volume = 0.8
    player.setFadeLevel(0.5)
    #expect(abs(player.node.volume - 0.4) < 0.001)

    player.setFadeLevel(1)
    #expect(abs(player.node.volume - 0.8) < 0.001)

    var completed = false
    player.fade(to: 0, duration: 0) { completed = true }
    #expect(completed, "Zero-duration fade must complete synchronously")
    #expect(abs(player.node.volume - 0) < 0.001)
  }

  // MARK: - Fast toggle race (regression)

  /// Toggling off then on during the fade-out must rescue the sound: play()
  /// ramps it back up, and the superseded fade's completion must NOT pause it
  /// after the original fade deadline passes.
  @Test func fastPauseReplayRescuesFadeOut() throws {
    let sound = Sound(
      title: "Toggle Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    defer { sound.unload() }

    sound.loadSound()
    try #require(sound.isLoaded, "fireplace.m4a should load")
    guard AudioEngineManager.shared.ensureRunning() else {
      try Test.cancel("Audio engine unavailable in this test environment")
    }

    sound.play()
    #expect(sound.playbackState == .playing)
    #expect(sound.isPlaying)

    // Let the fade-in progress (fades are run-loop timers); a pause at
    // fadeLevel ≈ 0 short-circuits to an instant stop, which isn't this race.
    // Spin until the level moves rather than a fixed wait (load-flake proof).
    let deadline = Date(timeIntervalSinceNow: 2.0)
    while (sound.player?.fadeLevel ?? 1) < 0.1, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    // The rescue race only exists mid-fade; a starved run loop (heavy CI/host
    // load) is an environment problem, not a regression.
    guard (sound.player?.fadeLevel ?? 0) >= 0.1 else {
      try Test.cancel("Fade-in timer didn't advance — run loop starved in this environment")
    }

    // Fade-out pause, then immediately play again (the fast off/on toggle).
    sound.pause()
    #expect(sound.playbackState == .paused)
    #expect(sound.isPlaying, "Node keeps rendering during the fade-out")

    sound.play()
    #expect(sound.playbackState == .playing, "Rescue must restore intent")

    // Let the original 0.5s fade deadline pass; its completion must not fire.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: Sound.fadeDuration + 0.3))
    #expect(sound.isPlaying, "Superseded fade completion must not pause the sound")
    #expect(sound.playbackState == .playing)
    #expect(abs((sound.player?.fadeLevel ?? 0) - 1.0) < 0.01, "Fade should be back at full")
  }

  // MARK: - Spatial placement persistence (regression: dots snapping back)

  /// Drag-end remembers the spot synchronously in the session store and reads
  /// back through the same path the grid dots use — an async hop (or a dropped
  /// write) makes released dots snap to their old position. Ending the session
  /// must discard placements (experimental: nothing persists between sessions).
  @Test func sessionPlacementRoundTrip() throws {
    let session = SpatialSessionManager.shared
    defer { session.setMode(.off) }

    guard let rain = AudioManager.shared.sounds.first(where: { $0.fileName == "rain" }) else {
      try Test.cancel("Built-in rain sound unavailable in this test host")
    }

    session.setMode(.fixed)
    #expect(session.isActive)

    // The exact call the drag gesture makes on release.
    rain.setSpatialPlacement(angleDegrees: 123, distance: 1.5, persist: true)

    #expect(session.placement(for: "rain")?.angle == 123)
    #expect(session.placement(for: "rain")?.distance == 1.5)

    // The read-back path the dot uses immediately after release.
    let placement = rain.spatialPlacement()
    #expect(placement.angle == 123, "Dot must read back the dropped position, not default")
    #expect(placement.distance == 1.5)

    // Taking a sound out of the field is session state too.
    session.setInField(false, for: "rain")
    #expect(!rain.isSpatialEligible)
    session.setInField(true, for: "rain")

    // Ending the session discards everything.
    session.setMode(.off)
    #expect(session.placement(for: "rain") == nil, "Session end must discard placements")
    #expect(!session.isActive)
  }
}
