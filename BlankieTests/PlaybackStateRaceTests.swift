//
//  PlaybackStateRaceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Pins the play-state races the modes and Now Playing models found. They cover
//  launch autoplay, the empty-mix pause, remote navigation while paused,
//  deferred "playing" publishes, and the foreground session under CarPlay.
//  Engine-free (TestSounds), with a recording Now Playing backend so nothing
//  reaches the system card.
//
//  Serialized and main-actor because it drives the AudioManager, PresetManager
//  and GlobalSettings singletons. Every touched value and key is restored in deinit.
//

import AVFoundation
import Foundation
import Testing

@testable import Blankie

/// Records what AudioManager publishes instead of publishing it.
@MainActor private final class RecordingNowPlaying: NowPlayingPublishing {
  private(set) var publishedStates: [Bool] = []

  func publishInfo(
    preset: Preset?, presetName: String?, creatorName: String?, artworkId: UUID?,
    isPlaying: Bool
  ) {
    publishedStates.append(isPlaying)
  }
  func republishCurrentPreset() {}
  func forceRefresh(preset: Preset, isPlaying: Bool) { publishedStates.append(isPlaying) }
  func updatePlaybackState(isPlaying: Bool) { publishedStates.append(isPlaying) }
  func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {}
  func clear() {}
  func installRemoteCommands(_ handlers: RemoteCommandHandlers) {}
  func setNavigationCommandsEnabled(_ enabled: Bool) {}
}

@Suite(.serialized) @MainActor final class PlaybackStateRaceTests {
  private let audioManager = AudioManager.shared
  private let recorder = RecordingNowPlaying()
  private let originalNowPlaying: (any NowPlayingPublishing)?
  private let originalSounds: [Sound]
  private let originalPresets: [Preset]
  private let originalCurrentPreset: Preset?
  private let originalStatesApplied: Bool
  private let snapshot = DefaultsSnapshot([
    UserDefaultsKeys.starredItems, UserDefaultsKeys.soloModeSoundFileName,
    PresetStorage.customPresetsKey, PresetStorage.defaultPresetKey,
    PresetStorage.lastActivePresetIDKey, "widgetSnapshot",
  ])
  nonisolated private static let testNames = ["test-a", "test-b"]

  init() {
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    originalNowPlaying = audioManager.nowPlayingManager
    originalSounds = audioManager.sounds
    originalPresets = PresetManager.shared.presets
    originalCurrentPreset = PresetManager.shared.currentPreset
    originalStatesApplied = PresetManager.shared.presetStatesApplied
    audioManager.nowPlayingManager = recorder
    audioManager.soloModeSound = nil
    audioManager.isQuickMix = false
    audioManager.isGloballyPlaying = false
    PresetManager.shared.setCurrentPreset(nil)
    PresetManager.shared.presetStatesApplied = false
  }

  isolated deinit {
    audioManager.isGloballyPlaying = false
    audioManager.soloModeSound = nil
    audioManager.sounds = originalSounds
    audioManager.nowPlayingManager = originalNowPlaying
    PresetManager.shared.setPresets(originalPresets)
    PresetManager.shared.setCurrentPreset(originalCurrentPreset)
    PresetManager.shared.presetStatesApplied = originalStatesApplied
    snapshot.restore()
    for name in Self.testNames {
      UserDefaults.shared.removeObject(forKey: "\(name)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(name)_volume")
    }
  }

  /// WidgetKit reloads as soon as an intent returns. Its snapshot must reflect
  /// the transition even while the system Now Playing backend is still delayed.
  @Test func widgetTransportSnapshotIsSynchronous() {
    let sound = TestSound(fileName: "test-a")
    audioManager.sounds = [sound]
    sound.isSelected = true
    let preset = PresetFactory.makePreset(
      name: "Widget Transport Probe",
      soundStates: [PresetState(fileName: sound.fileName, isSelected: true, volume: 0.5)],
      soundOrder: [sound.fileName])
    PresetManager.shared.setCurrentPreset(preset)
    audioManager.isGloballyPlaying = true
    audioManager.publishWidgetSnapshot(
      title: "Stale title", subtitle: nil, isPlaying: true, thumbnailKey: nil,
      accentColorName: nil)

    audioManager.setGlobalPlaybackState(false, forceUpdate: true)
    #expect(!WidgetStateStore.current().playback.isPlaying)
    #expect(WidgetStateStore.current().playback.title == preset.displayName)

    audioManager.setGlobalPlaybackState(true, forceUpdate: true)
    #expect(WidgetStateStore.current().playback.isPlaying)
    audioManager.setGlobalPlaybackState(false, forceUpdate: true)
    audioManager.republishWidgetCatalog()
    #expect(!WidgetStateStore.current().playback.isPlaying)

    sound.isSelected = false
    audioManager.setGlobalPlaybackState(true, forceUpdate: true)
    #expect(!WidgetStateStore.current().playback.isPlaying)
  }

  /// Selects `sound` while paused and lets its deferred auto-play check pass.
  private func selectWhilePaused(_ sound: Sound) async {
    sound.isSelected = true
    await spinMainLoop(timeout: 0.05)
  }

  // MARK: - Launch autoplay (F7)

  /// Autoplay on Open fires once per launch. After a play, selecting a sound
  /// into an emptied mix while paused leaves it paused.
  @Test func launchAutoplayDoesNotFireAfterAPlay() async {
    let originalAutoPlay = GlobalSettings.shared.autoPlayOnLaunch
    let originalHandled = audioManager.launchAutoPlayHandled
    defer {
      GlobalSettings.shared.setAutoPlayOnLaunch(originalAutoPlay)
      audioManager.launchAutoPlayHandled = originalHandled
    }
    let a = TestSound(fileName: "test-a")
    a.isSelected = true
    audioManager.sounds = [a]
    audioManager.launchAutoPlayHandled = false
    audioManager.setGlobalPlaybackState(true)
    audioManager.setGlobalPlaybackState(false)

    a.isSelected = false
    audioManager.updateHasSelectedSounds()
    GlobalSettings.shared.setAutoPlayOnLaunch(true)
    await selectWhilePaused(a)
    audioManager.updateHasSelectedSounds()
    await spinMainLoop(timeout: 0.2)

    #expect(!audioManager.isGloballyPlaying)
  }

  // MARK: - Empty mix (F5)

  /// F5: playback can start while the coalesced `hasSelectedSounds` is still
  /// false (the live gate already sees the selection). Clearing the mix before
  /// that pass lands leaves the flag unchanged, and the pause has to fire anyway.
  @Test func emptyMixPausesEvenWhenTheFlagNeverFlipped() async {
    let a = TestSound(fileName: "test-a")
    audioManager.sounds = [a]
    audioManager.updateHasSelectedSounds()
    #expect(!audioManager.hasSelectedSounds)

    a.isSelected = true  // the coalesced flag hasn't caught up
    audioManager.setGlobalPlaybackState(true)
    #expect(audioManager.isGloballyPlaying, "the live gate sees the selection")

    a.isSelected = false  // the next preset clears the mix first
    audioManager.updateHasSelectedSounds()
    for _ in 0..<100 where audioManager.isGloballyPlaying { await Task.yield() }

    #expect(!audioManager.isGloballyPlaying, "an empty mix must never stay playing")
  }

  // MARK: - Remote navigation while paused (F6)

  /// F6: skipping to the next favorite from the lock screen, Control Center
  /// or CarPlay while paused applies that preset's mix and stays paused.
  @Test func remoteNextWhilePausedStaysPaused() async throws {
    let a = TestSound(fileName: "test-a")
    let b = TestSound(fileName: "test-b")
    audioManager.sounds = [a, b]
    let first = PresetFactory.makePreset(
      name: "Nav A", soundStates: [PresetFactory.makeState(fileName: "test-a")],
      soundOrder: ["test-a"])
    let second = PresetFactory.makePreset(
      name: "Nav B", soundStates: [PresetFactory.makeState(fileName: "test-b")],
      soundOrder: ["test-b"])
    PresetManager.shared.setPresets([first, second])
    PresetManager.shared.setCurrentPreset(first)
    GlobalSettings.shared.setStarredItems([first.id.uuidString, second.id.uuidString])

    audioManager.navigateToNextPreset()
    await spinMainLoop(timeout: 1.0) {
      PresetManager.shared.currentPreset?.id == second.id && b.isSelected
    }
    try #require(b.isSelected, "the next favorite's mix is applied")
    await spinMainLoop(timeout: 0.2)  // past the apply Task's autoplay step

    #expect(!audioManager.isGloballyPlaying, "skipping while paused must not start playback")
  }

  // MARK: - Deferred publishes (N2)

  /// N2: playSelected defers its Now Playing update to a Task. A pause that
  /// lands first must not be overwritten by that Task's "playing".
  @Test func pauseBeforeTheDeferredPublishLeavesTheCardPaused() async {
    let a = TestSound(fileName: "test-a")
    audioManager.sounds = [a]
    await selectWhilePaused(a)

    audioManager.setGlobalPlaybackState(true)  // queues the deferred publish
    audioManager.setGlobalPlaybackState(false)
    for _ in 0..<50 { await Task.yield() }

    #expect(recorder.publishedStates.contains(true))
    #expect(recorder.publishedStates.last == false, "the last publish must be the pause")
  }

  /// N2's solo branch, with the same ordering while a sound plays by itself.
  @Test func pauseBeforeTheDeferredSoloPublishLeavesTheCardPaused() async {
    let a = TestSound(fileName: "test-a")
    audioManager.sounds = [a]
    await selectWhilePaused(a)
    audioManager.soloModeSound = a

    audioManager.setGlobalPlaybackState(true)
    audioManager.setGlobalPlaybackState(false)
    for _ in 0..<50 { await Task.yield() }

    #expect(recorder.publishedStates.last == false, "the last publish must be the pause")
  }

  // MARK: - Foreground session under CarPlay (P8)

  #if os(iOS)
    /// P8: coming back to the foreground re-applies the session rules, so Mix
    /// with Other Audio stays off while CarPlay is connected.
    @Test func foregroundUnderCarPlayKeepsExclusiveAudio() throws {
      let session = AVAudioSession.sharedInstance()
      let originalMix = GlobalSettings.shared.mixWithOthers
      defer {
        audioManager.isGloballyPlaying = false
        audioManager.setCarPlayConnected(false)
        GlobalSettings.shared.mixWithOthers = originalMix
      }

      AudioSessionManager.shared.setupForPlayback(mixWithOthers: true, isCarPlayConnected: false)
      guard session.categoryOptions.contains(.mixWithOthers) else {
        try Test.cancel("This host can't configure the audio session")
      }

      GlobalSettings.shared.mixWithOthers = true
      audioManager.setCarPlayConnected(true)  // paused, so the session is untouched
      audioManager.isGloballyPlaying = true
      audioManager.handleWillEnterForeground()
      audioManager.isGloballyPlaying = false  // before its deferred refresh runs

      #expect(
        !session.categoryOptions.contains(.mixWithOthers),
        "CarPlay keeps the session exclusive after returning to the foreground")
    }
  #endif
}
