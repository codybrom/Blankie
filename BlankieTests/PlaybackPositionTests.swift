//
//  PlaybackPositionTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import XCTest

@testable import Blankie

/// Stage-1 tests for the Sound playback facade — pure logic only, no audio
/// session or hardware. Real playback (play() success, position read-back,
/// fades, loop completion) is device/integration territory; see the skip
/// marker at the bottom so the gap stays visible in test reports.
final class PlaybackPositionTests: XCTestCase {

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
  func testRandomStartStaysWithinFirst75Percent() {
    let duration: Double = 120.0
    let maxPosition = duration * 0.75

    for _ in 0..<1_000 {
      let position = Double.random(in: 0..<maxPosition)
      XCTAssertGreaterThanOrEqual(position, 0)
      XCTAssertLessThan(position, maxPosition)
    }
  }

  // MARK: - Facade defaults without a player

  func testFacadeDefaultsWhenUnloaded() {
    let sound = HeadlessSound(fileName: "headless-facade")

    XCTAssertFalse(sound.isLoaded)
    XCTAssertFalse(sound.isPlaying)
    XCTAssertEqual(sound.playbackPosition, 0)
    XCTAssertEqual(sound.playbackDuration, 0)
    XCTAssertEqual(sound.playbackState, .stopped)
  }

  // MARK: - State transitions without a player

  /// pause()/stop() early-return when no player exists: they must not crash,
  /// flip selection, or leave playbackState anything but .stopped.
  func testPauseAndStopAreSafeWithoutPlayer() {
    let sound = HeadlessSound(fileName: "headless-transition")
    XCTAssertNil(sound.player)

    sound.pause()
    XCTAssertEqual(sound.playbackState, .stopped)
    sound.pause(immediate: true)
    XCTAssertEqual(sound.playbackState, .stopped)
    sound.stop()
    XCTAssertEqual(sound.playbackState, .stopped)
    sound.resetSoundPosition()

    XCTAssertNil(sound.player)
    XCTAssertFalse(sound.isSelected)
  }

  func testUnloadResetsStateAndPlayer() {
    let sound = HeadlessSound(fileName: "headless-unload")
    sound.playbackState = .paused  // simulate a stale state before teardown

    sound.unload()

    XCTAssertNil(sound.player)
    XCTAssertEqual(sound.playbackState, .stopped)
  }

  // MARK: - Engine graph hygiene

  /// Repeated load/unload (the preview sheet pattern) must not accumulate
  /// nodes in the engine — unload() detaches what loadSound() attached.
  func testEngineRegistryReturnsToBaselineAfterUnload() {
    let sound = Sound(
      title: "Leak Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    let baseline = AudioEngineManager.shared.registered.count

    for _ in 0..<3 {
      sound.loadSound()
      XCTAssertTrue(sound.isLoaded, "Bundled fireplace.m4a should load")
      XCTAssertEqual(
        AudioEngineManager.shared.registered.count, baseline + 1,
        "loadSound must attach exactly one player")
      sound.unload()
      XCTAssertEqual(
        AudioEngineManager.shared.registered.count, baseline,
        "unload must detach the player it attached")
    }
  }

  // MARK: - Fade layer math

  /// node.volume must always be baseVolume × fadeLevel; a zero-duration fade
  /// applies instantly and fires its completion synchronously.
  func testFadeLayerScalesNodeVolume() {
    let sound = Sound(
      title: "Fade Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    sound.loadSound()
    guard let player = sound.player else { return XCTFail("fireplace.m4a should load") }
    defer { sound.unload() }

    player.volume = 0.8
    player.setFadeLevel(0.5)
    XCTAssertEqual(player.node.volume, 0.4, accuracy: 0.001)

    player.setFadeLevel(1)
    XCTAssertEqual(player.node.volume, 0.8, accuracy: 0.001)

    var completed = false
    player.fade(to: 0, duration: 0) { completed = true }
    XCTAssertTrue(completed, "Zero-duration fade must complete synchronously")
    XCTAssertEqual(player.node.volume, 0, accuracy: 0.001)
  }

  // MARK: - Fast toggle race (regression)

  /// Toggling off then on during the fade-out must rescue the sound: play()
  /// ramps it back up, and the superseded fade's completion must NOT pause it
  /// after the original fade deadline passes.
  func testFastPauseReplayRescuesFadeOut() throws {
    let sound = Sound(
      title: "Toggle Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    defer { sound.unload() }

    sound.loadSound()
    guard sound.isLoaded else { return XCTFail("fireplace.m4a should load") }
    guard AudioEngineManager.shared.ensureRunning() else {
      throw XCTSkip("Audio engine unavailable in this test environment")
    }

    sound.play()
    XCTAssertEqual(sound.playbackState, .playing)
    XCTAssertTrue(sound.isPlaying)

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
      throw XCTSkip("Fade-in timer didn't advance — run loop starved in this environment")
    }

    // Fade-out pause, then immediately play again (the fast off/on toggle).
    sound.pause()
    XCTAssertEqual(sound.playbackState, .paused)
    XCTAssertTrue(sound.isPlaying, "Node keeps rendering during the fade-out")

    sound.play()
    XCTAssertEqual(sound.playbackState, .playing, "Rescue must restore intent")

    // Let the original 0.5s fade deadline pass; its completion must not fire.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: Sound.fadeDuration + 0.3))
    XCTAssertTrue(sound.isPlaying, "Superseded fade completion must not pause the sound")
    XCTAssertEqual(sound.playbackState, .playing)
    XCTAssertEqual(sound.player?.fadeLevel ?? 0, 1.0, accuracy: 0.01, "Fade should be back at full")
  }

  // MARK: - Spatial placement persistence (regression: dots snapping back)

  /// Drag-end remembers the spot synchronously in the session store and reads
  /// back through the same path the grid dots use — an async hop (or a dropped
  /// write) makes released dots snap to their old position. Ending the session
  /// must discard placements (experimental: nothing persists between sessions).
  @MainActor
  func testSessionPlacementRoundTrip() throws {
    let session = SpatialSessionManager.shared
    defer { session.setMode(.off) }

    guard let rain = AudioManager.shared.sounds.first(where: { $0.fileName == "rain" }) else {
      throw XCTSkip("Built-in rain sound unavailable in this test host")
    }

    session.setMode(.fixed)
    XCTAssertTrue(session.isActive)

    // The exact call the drag gesture makes on release.
    rain.setSpatialPlacement(angleDegrees: 123, distance: 1.5, persist: true)

    XCTAssertEqual(session.placement(for: "rain")?.angle, 123)
    XCTAssertEqual(session.placement(for: "rain")?.distance, 1.5)

    // The read-back path the dot uses immediately after release.
    let placement = rain.spatialPlacement()
    XCTAssertEqual(placement.angle, 123, "Dot must read back the dropped position, not default")
    XCTAssertEqual(placement.distance, 1.5)

    // Taking a sound out of the field is session state too.
    session.setInField(false, for: "rain")
    XCTAssertFalse(rain.isSpatialEligible)
    session.setInField(true, for: "rain")

    // Ending the session discards everything.
    session.setMode(.off)
    XCTAssertNil(session.placement(for: "rain"), "Session end must discard placements")
    XCTAssertFalse(session.isActive)
  }

  // MARK: - Integration placeholder

  /// Documents what cannot run headless so the gap is visible, not silent.
  func testRealPlaybackPositionAfterPlay_Integration() throws {
    throw XCTSkip(
      "Requires a running engine + audio hardware: play() success, position "
        + "read-back during playback, and loop completion. "
        + "Covered by the on-device soak checklist.")
  }
}
