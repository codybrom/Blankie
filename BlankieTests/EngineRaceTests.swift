//
//  EngineRaceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Engine start retries, the mid-fade rescue and the post-preview idle pass. Needs the real
//  shared engine and a bundled sound. Cancels where the host has no audio output.
//  Serialized: preset saves are off for the suite so the probe never lands in a real preset.
//

import AVFoundation
import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class EngineRaceTests {
  private let audioManager = AudioManager.shared
  private let engineManager = AudioEngineManager.shared
  private let originalSounds: [Sound]
  private let originalCurrentPreset: Preset?
  private let originalStatesApplied: Bool
  private let snapshot = DefaultsSnapshot(["fireplace_isSelected", "fireplace_volume"])
  private var probe: Sound?

  private struct StartFailure: Error {}

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalSounds = audioManager.sounds
    originalCurrentPreset = PresetManager.shared.currentPreset
    originalStatesApplied = PresetManager.shared.presetStatesApplied
    PresetManager.shared.setCurrentPreset(nil)
    PresetManager.shared.presetStatesApplied = false
    audioManager.singleSound = nil
    audioManager.isGloballyPlaying = false
    engineManager.pause()
  }

  isolated deinit {
    engineManager.startEngine = { try $0.start() }
    audioManager.isGloballyPlaying = false
    probe?.unload()
    audioManager.previewModeSound = nil
    audioManager.previewModeOriginalStates.removeAll()
    audioManager.sounds = originalSounds
    engineManager.pause()
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
    PresetManager.shared.presetStatesApplied = originalStatesApplied
    snapshot.restore()
  }

  /// A loaded bundled sound, or cancels when this host can't run the engine.
  private func makeProbe() throws -> Sound {
    let sound = Sound(
      title: "Race Probe", systemIconName: "speaker.wave.2",
      fileName: "fireplace", fileExtension: "m4a")
    sound.loadSound()
    try #require(sound.isLoaded, "fireplace.m4a should load")
    guard engineManager.ensureRunning() else {
      try Test.cancel("Audio engine unavailable in this test environment")
    }
    engineManager.pause()
    probe = sound
    return sound
  }

  // MARK: - Start retry

  /// Restarting the engine over silence makes iOS report the app as playing.
  @Test func startRetryAfterPauseLeavesEngineIdle() async throws {
    _ = try makeProbe()
    engineManager.startEngine = { _ in throw StartFailure() }
    audioManager.isGloballyPlaying = true
    #expect(!engineManager.ensureRunning(), "the injected failure schedules a retry")
    guard case .failed(retryCount: 1) = engineManager.state else {
      Issue.record("this test's failure should schedule the first retry")
      return
    }

    engineManager.startEngine = { try $0.start() }
    audioManager.isGloballyPlaying = false  // the user pauses before the retry
    // The retry fires at 0.25 s. Wait well past it, or until it restarts the engine.
    await spinMainLoop(timeout: 1.5) { self.engineManager.engine.isRunning }

    #expect(!engineManager.engine.isRunning, "the retry must not restart a paused engine")
  }

  /// When a configuration rebuild restarts the engine first, the retry still resumes the sound.
  @Test func startRetryResumesSoundAfterRebuildRestartedEngine() async throws {
    let sound = try makeProbe()
    audioManager.sounds = [sound]
    engineManager.startEngine = { _ in throw StartFailure() }
    audioManager.isGloballyPlaying = true
    // Selecting while playing auto-plays the sound, and its failed start
    // schedules the retry. Nothing else will start it after this.
    sound.isSelected = true
    await spinMainLoop(timeout: 2) {
      if case .failed = self.engineManager.state { true } else { false }
    }
    #expect(!sound.isPlaying, "the failed start leaves the sound silent")

    engineManager.startEngine = { try $0.start() }
    #expect(engineManager.ensureRunning(), "the rebuild brings the engine back first")
    // The retry fires at 0.25 s. Allow for a loaded host.
    await spinMainLoop(timeout: 3) { sound.isPlaying }

    #expect(sound.isPlaying, "the retry must resume the sound the failed start left silent")
    audioManager.isGloballyPlaying = false
    sound.pause(immediate: true)
  }

  /// Each sound's play() reaches ensureRunning, so one failed pass over six sounds must not
  /// spend the five-retry budget. Six calls stand in for playSelected.
  @Test func oneFailedStartAcrossManySoundsKeepsTheRetryBudget() async throws {
    _ = try makeProbe()  // a successful start resets the retry count
    let rain = TestSound(fileName: "test-a")
    audioManager.sounds = [rain]
    rain.isSelected = true
    await spinMainLoop(timeout: 0.05)

    engineManager.startEngine = { _ in throw StartFailure() }
    audioManager.isGloballyPlaying = true
    for _ in 0..<6 { _ = engineManager.ensureRunning() }
    for _ in 0..<20 { await Task.yield() }

    #expect(audioManager.isGloballyPlaying, "one failed pass must not give up on playback")
    engineManager.startEngine = { try $0.start() }
    audioManager.isGloballyPlaying = false  // pending retries bail on the pause
    rain.isSelected = false
    UserDefaults.shared.removeObject(forKey: "test-a_isSelected")
  }

  // MARK: - Mid-fade rescue

  /// The idle-pause safety net can pause the engine under a node that is still fading
  /// out. Replaying then takes the rescue branch.
  @Test func rescuingAMidFadePauseRestartsTheEngine() async throws {
    let sound = try makeProbe()
    #expect(engineManager.ensureRunning())
    sound.play()

    await spinMainLoop(timeout: 2.0) { (sound.player?.fadeLevel ?? 1) >= 0.1 }
    guard (sound.player?.fadeLevel ?? 0) >= 0.1 else {
      try Test.cancel("Fade-in timer didn't advance; run loop starved in this environment")
    }

    sound.pause()
    try #require(sound.isPlaying, "the node keeps rendering during the fade-out")
    engineManager.pause()  // the forced safety-net pause
    guard sound.isPlaying else {
      try Test.cancel("This host stops the node with the engine; the rescue branch is unreachable")
    }

    sound.play()

    #expect(sound.playbackState == .playing)
    #expect(engineManager.engine.isRunning, "the rescue must restart the paused engine")
    sound.pause(immediate: true)
  }

  // MARK: - Preview while paused

  @Test func leavingAPreviewWhilePausedIdlesTheEngine() async throws {
    let sound = try makeProbe()
    audioManager.sounds = [sound]

    audioManager.enterPreviewMode(for: sound)
    try #require(engineManager.engine.isRunning, "the preview starts the engine")

    audioManager.exitPreviewMode()
    await spinMainLoop(timeout: 5.0) { !self.engineManager.engine.isRunning }

    #expect(!engineManager.engine.isRunning, "the engine idles after the preview fades out")
  }
}
