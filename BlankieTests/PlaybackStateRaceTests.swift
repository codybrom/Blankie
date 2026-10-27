//
//  PlaybackStateRaceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Play-state races: launch autoplay, the empty-mix pause, remote navigation while paused,
//  deferred "playing" publishes and the foreground session under CarPlay. Engine-free, with a
//  recording Now Playing backend. Serialized: deinit restores every touched value and key.
//

import AVFoundation
import Foundation
import Testing

@testable import Blankie

/// Records what AudioManager publishes without reaching the system card.
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

  // MARK: - Launch autoplay

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

  // MARK: - Empty mix

  /// Playback can start before the coalesced `hasSelectedSounds` flips, so clearing the mix
  /// leaves the flag unchanged and the pause still has to fire.
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

  // MARK: - Remote navigation while paused

  /// Covers next from the lock screen, Control Center and CarPlay.
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

  // MARK: - Deferred publishes

  /// playSelected defers its Now Playing update to a Task, which must not overwrite an
  /// earlier pause.
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

  /// The same ordering through the solo branch.
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

  // MARK: - Foreground session under CarPlay

  #if os(iOS)
    /// Returning to the foreground re-applies the session rules, which keep Mix with Other
    /// Audio off under CarPlay.
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
