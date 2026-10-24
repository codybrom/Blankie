//
//  PresetEntryTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Pins how presets, Quick Mix, and the sound-editor preview hand playback to
//  each other. It checks that an application reports whether it ran, so callers
//  don't start the old mix. It also checks that leaving Quick Mix for a preset
//  drops the pre-Quick-Mix mix, a pending edit is saved before Quick Mix,
//  deleting the current preset while paused stays paused, a stale widget tile
//  leaves solo alone, playPreset starts a current preset (also after a relaunch
//  into solo), Play Sound joins a custom preset, an invalid preset
//  leaves Quick Mix alone, and play/pause or a preset command ends a preview
//  (an ignored play or an emptied mix doesn't, and solo out of one keeps playing).
//
//  Engine-free (TestSounds), serialized and main-actor, on an isolated preset
//  list (SingletonSandbox).
//

import Foundation
import Testing

@testable import Blankie

#if os(iOS) || os(visionOS)
  import AVFoundation
#endif

@Suite(.serialized) @MainActor final class PresetEntryTests {
  private let sandbox: SingletonSandbox
  private let originalStarredItems: [String]
  #if os(iOS) || os(visionOS)
    private let originalInterrupted: Bool
  #endif
  private var audioManager: AudioManager { sandbox.audioManager }
  private var presetManager: PresetManager { sandbox.presetManager }

  init() async {
    sandbox = await SingletonSandbox.make(
      soundNames: ["test-entry-a", "test-entry-b", "test-entry-preview"])
    originalStarredItems = GlobalSettings.shared.starredItems
    #if os(iOS) || os(visionOS)
      originalInterrupted = AudioManager.shared.wasPlayingWhenInterrupted
      audioManager.wasPlayingWhenInterrupted = false
    #endif
  }

  isolated deinit {
    sandbox.restore()
    GlobalSettings.shared.setStarredItems(originalStarredItems)
    #if os(iOS) || os(visionOS)
      audioManager.wasPlayingWhenInterrupted = originalInterrupted
    #endif
  }

  // MARK: - Helpers

  /// Returns two sounds, with `a` selected.
  private func makeSounds() -> (a: TestSound, b: TestSound) {
    let a = TestSound(fileName: "test-entry-a")
    a.isSelected = true
    a.volume = 0.5
    let b = TestSound(fileName: "test-entry-b")
    audioManager.sounds = [a, b]
    return (a, b)
  }

  private func preset(_ name: String, selecting selected: Set<String>, from sounds: [Sound])
    -> Preset
  {
    PresetFactory.makePreset(
      name: name,
      soundStates: sounds.map {
        PresetState(fileName: $0.fileName, isSelected: selected.contains($0.fileName), volume: 0.5)
      },
      soundOrder: sounds.map(\.fileName))
  }

  /// Installs `presets`, makes the first current and fully applied.
  private func install(_ presets: [Preset]) async {
    presetManager.setPresets(presets)
    presetManager.setCurrentPreset(presets.first)
    presetManager.presetStatesApplied = true
    await sandbox.settle()
  }

  // MARK: - applyPreset reports whether it ran (F1)

  /// Callers start playback only when nothing was applied. An application starts
  /// the new mix itself, and playing first would start the old one.
  @Test func applyPresetReportsWhetherItApplied() async throws {
    let (a, b) = makeSounds()
    let first = preset("Entry One", selecting: [a.fileName], from: [a, b])
    let second = preset("Entry Two", selecting: [b.fileName], from: [a, b])
    await install([first, second])

    #expect(try presetManager.applyPreset(first) == false)
    #expect(try presetManager.applyPreset(second) == true)
    await sandbox.waitForPresetApply()
    #expect(b.isSelected)
    #expect(!a.isSelected)
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Quick Mix exits (F3)

  /// Leaving Quick Mix for a preset drops the pre-Quick-Mix mix and preset, so
  /// the preset about to apply isn't preceded by the old mix (or short-circuited
  /// when it's the same preset).
  @Test func leavingQuickMixForAPresetDropsTheOldMix() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM", selecting: [a.fileName], from: [a, b])
    await install([current])

    audioManager.enterQuickMix()
    audioManager.leaveTransientModes()

    #expect(!audioManager.isQuickMix)
    #expect(presetManager.currentPreset == nil)
    #expect(!a.isSelected)
    #expect(a.volume == 0.5)
  }

  /// A preset that's already current applies nothing, so playPreset starts it.
  @Test func playPresetStartsTheCurrentPreset() async throws {
    let (a, b) = makeSounds()
    let current = preset("Entry Current", selecting: [a.fileName], from: [a, b])
    await install([current])
    #expect(!audioManager.isGloballyPlaying)

    try presetManager.playPreset(current)

    #expect(audioManager.isGloballyPlaying)
    audioManager.setGlobalPlaybackState(false)
  }

  /// A preset that fails validation throws before leaving Quick Mix, so the
  /// earlier mix isn't dropped for nothing.
  @Test func invalidPresetLeavesQuickMixAlone() async {
    let (a, b) = makeSounds()
    await install([preset("Entry QM Invalid", selecting: [a.fileName], from: [a, b])])
    let invalid = PresetFactory.makePreset(
      name: "Entry Missing",
      soundStates: [PresetState(fileName: "test-entry-missing", isSelected: true, volume: 0.5)],
      soundOrder: ["test-entry-missing"])

    audioManager.enterQuickMix()
    #expect(throws: PresetError.self) { try self.presetManager.playPreset(invalid) }

    #expect(audioManager.isQuickMix)
    audioManager.exitQuickMix()
  }

  /// The default exit (Quick Mix's own close) still restores the earlier mix.
  @Test func exitingQuickMixRestoresThePreset() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM Restore", selecting: [a.fileName], from: [a, b])
    await install([current])

    audioManager.enterQuickMix()
    audioManager.exitQuickMix()

    #expect(presetManager.currentPreset?.id == current.id)
    #expect(a.isSelected)
  }

  /// Entering Quick Mix saves the edit still waiting on the coalesced refresh.
  /// Quick Mix clears the current preset, so the refresh would skip it.
  @Test func enteringQuickMixSavesThePendingEdit() async {
    let (a, b) = makeSounds()
    let current = preset("Entry QM Flush", selecting: [a.fileName], from: [a, b])
    await install([current])

    a.volume = 0.3
    audioManager.enterQuickMix()

    let saved = presetManager.presets.first { $0.id == current.id }?
      .soundStates.first { $0.fileName == a.fileName }?.volume
    #expect(saved == 0.3)
    audioManager.exitQuickMix()
  }

  // MARK: - Deleting the current preset (D1)

  /// Deleting the current preset while paused makes the next one current
  /// without starting it.
  @Test func deletingTheCurrentPresetWhilePausedStaysPaused() async {
    let (a, b) = makeSounds()
    let doomed = preset("Entry Doomed", selecting: [a.fileName], from: [a, b])
    let next = preset("Entry Next", selecting: [b.fileName], from: [a, b])
    await install([doomed, next])
    #expect(!audioManager.isGloballyPlaying)

    presetManager.deletePreset(doomed)
    await sandbox.waitForPresetApply()

    #expect(presetManager.currentPreset?.id == next.id)
    #expect(!audioManager.isGloballyPlaying)
  }

  // MARK: - Stale widget tile (X2)

  /// A tile for a deleted preset throws before leaving solo, so the soloed
  /// sound isn't left paused under a "playing" state.
  @Test func staleWidgetTileLeavesSoloAlone() async {
    let (a, b) = makeSounds()
    await install([preset("Entry Solo", selecting: [a.fileName], from: [a, b])])
    audioManager.enterSoloMode(for: b, startPlaying: false)

    let intent = WidgetPlayFavoriteIntent(favoriteToken: UUID().uuidString)
    await #expect(throws: BlankieIntentError.self) { _ = try await intent.perform() }

    #expect(audioManager.soloModeSound === b)
    audioManager.exitSoloModeWithoutResuming()
  }

  // MARK: - Siri and solo

  /// Siri plays a sound on its own, just like a sound in Favorites. It must not
  /// add that sound to the active preset or save its temporary solo state.
  @Test func playSoundSolosWithoutChangingTheCurrentCustomPreset() async throws {
    let (a, b) = makeSounds()
    let current = preset("Entry Siri", selecting: [a.fileName], from: [a])
    await install([current])

    var intent = PlaySoundIntent()
    intent.sound = SoundEntity(sound: b)
    _ = try await intent.perform()
    await sandbox.settle()

    #expect(audioManager.soloModeSound === b)
    #expect(audioManager.isGloballyPlaying)
    #expect(b.isSelected)
    #expect(presetManager.currentPreset?.id == current.id)
    #expect(presetManager.currentPreset?.soundStates == current.soundStates)
    #expect(presetManager.presets.first { $0.id == current.id }?.soundStates == current.soundStates)

    audioManager.exitSoloModeWithoutResuming()
    #expect(!b.isSelected)
    #expect(a.isSelected)
    audioManager.setGlobalPlaybackState(false)
  }

  /// Repeating a deterministic Play Sound command resumes a paused solo rather
  /// than toggling it off or leaving it paused.
  @Test func playSoundResumesTheSamePausedSolo() async throws {
    let (a, b) = makeSounds()
    await install([preset("Entry Siri Resume", selecting: [a.fileName], from: [a])])
    audioManager.enterSoloMode(for: b, startPlaying: false)

    var intent = PlaySoundIntent()
    intent.sound = SoundEntity(sound: b)
    _ = try await intent.perform()

    #expect(audioManager.soloModeSound === b)
    #expect(audioManager.isGloballyPlaying)
    audioManager.exitSoloModeWithoutResuming()
    #expect(!b.isSelected)
    audioManager.setGlobalPlaybackState(false)
  }

  /// A sound command leaves Quick Mix through the normal solo transition,
  /// retaining the saved preset rather than adding a sound to its membership.
  @Test func playSoundLeavesQuickMixForSolo() async throws {
    let (a, b) = makeSounds()
    let current = preset("Entry Siri Quick Mix", selecting: [a.fileName], from: [a])
    await install([current])
    audioManager.enterQuickMix()

    var intent = PlaySoundIntent()
    intent.sound = SoundEntity(sound: b)
    _ = try await intent.perform()

    #expect(!audioManager.isQuickMix)
    #expect(audioManager.soloModeSound === b)
    #expect(audioManager.isGloballyPlaying)
    #expect(presetManager.currentPreset?.id == current.id)
    #expect(presetManager.presets.first { $0.id == current.id }?.soundStates == current.soundStates)
    audioManager.exitSoloModeWithoutResuming()
    audioManager.setGlobalPlaybackState(false)
  }

  /// A relaunch into solo skips the preset's apply. Playing that same preset
  /// re-applies its selection on the way out of solo, so the mix plays.
  @Test func playPresetAfterARelaunchIntoSoloPlaysThePreset() async throws {
    let (a, b) = makeSounds()
    let current = preset("Entry Relaunch", selecting: [a.fileName], from: [a, b])
    await install([current])
    presetManager.presetStatesApplied = false  // as after a relaunch into solo
    a.isSelected = false
    audioManager.enterSoloMode(for: b, startPlaying: false)

    try presetManager.playPreset(current)

    #expect(audioManager.soloModeSound == nil)
    #expect(a.isSelected)
    #expect(!b.isSelected)
    #expect(audioManager.isGloballyPlaying)
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Commands end a preview (F2)

  /// Play/pause from anywhere ends the sound-editor preview first.
  @Test func playbackCommandEndsThePreview() async {
    _ = makeSounds()
    audioManager.previewModeSound = TestSound(fileName: "test-entry-preview")

    audioManager.setGlobalPlaybackState(false)

    #expect(audioManager.previewModeSound == nil)
  }

  /// A play ignored because nothing is selected leaves the preview playing.
  @Test func ignoredPlayLeavesThePreview() async {
    let (a, _) = makeSounds()
    a.isSelected = false
    audioManager.previewModeSound = TestSound(fileName: "test-entry-preview")

    audioManager.setGlobalPlaybackState(true)
    #expect(audioManager.previewModeSound != nil)

    audioManager.setGlobalPlaybackState(false)
    #expect(audioManager.previewModeSound == nil)
  }

  /// The editor can deselect the sound it previews. The empty-mix pause waits
  /// for the preview to end instead of cutting it off.
  @Test func emptiedMixPausesAfterThePreview() async {
    let (a, _) = makeSounds()
    audioManager.setGlobalPlaybackState(true)
    audioManager.previewModeSound = a

    a.isSelected = false
    audioManager.updateHasSelectedSounds()
    await sandbox.settle()
    #expect(audioManager.isGloballyPlaying)
    #expect(audioManager.previewModeSound === a)

    audioManager.exitPreviewMode(resuming: false)
    await sandbox.settle()
    #expect(!audioManager.isGloballyPlaying)
  }

  /// Entering solo ends the preview and queues the empty-mix pause before the
  /// solo sound starts. The pause checks again when it runs, so solo keeps playing.
  @Test func soloFromAnEmptiedPreviewKeepsPlaying() async {
    let (a, b) = makeSounds()
    audioManager.setGlobalPlaybackState(true)
    audioManager.previewModeSound = a
    a.isSelected = false
    audioManager.updateHasSelectedSounds()

    audioManager.enterSoloMode(for: b)
    await sandbox.settle()

    #expect(audioManager.soloModeSound === b)
    #expect(audioManager.isGloballyPlaying)
    audioManager.exitSoloModeWithoutResuming()
    audioManager.setGlobalPlaybackState(false)
  }

  /// Applying a preset ends the preview before the new mix goes in.
  @Test func presetCommandEndsThePreview() async throws {
    let (a, b) = makeSounds()
    let first = preset("Entry Preview One", selecting: [a.fileName], from: [a, b])
    let second = preset("Entry Preview Two", selecting: [b.fileName], from: [a, b])
    await install([first, second])
    audioManager.previewModeSound = TestSound(fileName: "test-entry-preview")

    try presetManager.applyPreset(second)
    #expect(audioManager.previewModeSound == nil)
    await sandbox.waitForPresetApply()
    audioManager.setGlobalPlaybackState(false)
  }

  // MARK: - Interruption resume (F4)

  #if os(iOS) || os(visionOS)
    @Test(arguments: [false, true])
    func carVolumeStaysHiddenUntilBothSceneAndRouteDisconnect(routeConnectsFirst: Bool) {
      let originalConnected = audioManager.isCarPlayConnected
      defer {
        audioManager.setCarAudioRouteActive(false)
        audioManager.setCarPlayConnected(originalConnected)
      }
      audioManager.setCarPlayConnected(false)
      audioManager.setCarAudioRouteActive(false)
      #expect(!audioManager.isCarPlayConnected)
      if routeConnectsFirst {
        audioManager.setCarAudioRouteActive(true)
      } else {
        audioManager.setCarPlayConnected(true)
      }
      #expect(audioManager.isCarPlayConnected)
      audioManager.setCarAudioRouteActive(true)
      audioManager.setCarPlayConnected(true)
      if routeConnectsFirst {
        audioManager.setCarAudioRouteActive(false)
      } else {
        audioManager.setCarPlayConnected(false)
      }
      #expect(audioManager.isCarPlayConnected)
      audioManager.setCarAudioRouteActive(false)
      audioManager.setCarPlayConnected(false)
      #expect(!audioManager.isCarPlayConnected)
    }

    private func interrupt(_ type: AVAudioSession.InterruptionType, resume: Bool? = nil) {
      var info: [String: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
      if let resume {
        info[AVAudioSessionInterruptionOptionKey] =
          resume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : UInt(0)
      }
      audioManager.handleAudioInterruption(
        Notification(name: AVAudioSession.interruptionNotification, userInfo: info))
    }

    @Test(arguments: [false, true])
    func interruptionResumesOnlyIfPlaybackWasActive(wasPlaying: Bool) {
      _ = makeSounds()
      audioManager.setGlobalPlaybackState(wasPlaying)
      interrupt(.began)
      #expect(!audioManager.isGloballyPlaying)
      interrupt(.ended, resume: true)
      #expect(audioManager.isGloballyPlaying == wasPlaying)
      #expect(!audioManager.wasPlayingWhenInterrupted)
      audioManager.setGlobalPlaybackState(false)
    }

    @Test func pauseDuringInterruptionPreventsAutomaticResume() {
      _ = makeSounds()
      audioManager.setGlobalPlaybackState(true)
      interrupt(.began)
      #expect(audioManager.wasPlayingWhenInterrupted)
      audioManager.setGlobalPlaybackState(false)
      interrupt(.ended, resume: true)
      #expect(!audioManager.isGloballyPlaying)
    }

    @Test func sleepTimerExpiryDuringInterruptionPreventsAutomaticResume() async {
      _ = makeSounds()
      let timer = TimerManager.shared
      let now = Date(timeIntervalSince1970: 1000)
      defer {
        timer.stopTimer()
        timer.now = { Date() }
      }
      audioManager.setGlobalPlaybackState(true)
      timer.now = { now }
      timer.startTimer(duration: 60)
      interrupt(.began)
      timer.now = { now.addingTimeInterval(61) }
      timer.tick()
      for _ in 0..<100 where timer.isTimerActive { await Task.yield() }
      #expect(!timer.isTimerActive)
      interrupt(.ended, resume: true)
      #expect(!audioManager.isGloballyPlaying)
    }

    @Test(arguments: [false, true])
    func interruptionEndWithoutResumeConsumesPendingRecovery(includeOptions: Bool) {
      _ = makeSounds()
      audioManager.setGlobalPlaybackState(true)
      interrupt(.began)
      interrupt(.ended, resume: includeOptions ? false : nil)
      #expect(!audioManager.wasPlayingWhenInterrupted)
      // A duplicate/stale end must not resurrect the consumed request.
      interrupt(.ended, resume: true)
      #expect(!audioManager.isGloballyPlaying)
    }

    @Test func headphoneDisconnectDuringInterruptionPreventsAutomaticResume() {
      _ = makeSounds()
      audioManager.setGlobalPlaybackState(true)
      interrupt(.began)
      audioManager.handleAudioRouteChange(
        Notification(
          name: AVAudioSession.routeChangeNotification,
          userInfo: [
            AVAudioSessionRouteChangeReasonKey:
              AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
          ]))
      interrupt(.ended, resume: true)
      #expect(!audioManager.isGloballyPlaying)
    }

    @Test(arguments: [false, true])
    func previewObservesAndStopsForInterruptionsAndHeadphoneRemoval(disconnect: Bool) {
      let (_, preview) = makeSounds()
      audioManager.enterPreviewMode(for: preview)
      #expect(audioManager.audioSessionObserversSetup)
      #expect(audioManager.previewModeSound === preview)
      let note =
        disconnect
        ? Notification(
          name: AVAudioSession.routeChangeNotification,
          userInfo: [
            AVAudioSessionRouteChangeReasonKey:
              AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
          ])
        : Notification(
          name: AVAudioSession.interruptionNotification,
          userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
          ])
      NotificationCenter.default.post(note)
      #expect(audioManager.previewModeSound == nil)
      #expect(!audioManager.isGloballyPlaying)
      #expect(!audioManager.wasPlayingWhenInterrupted)
    }

    @Test func resetConfigurationDoesNotActivateUntilPlaybackIsRequested() {
      var configurations: [AVAudioSession.CategoryOptions] = []
      var activations: [Bool] = []
      let session = AudioSessionManager(
        setCategory: { category, mode, options in
          #expect(category == .playback)
          #expect(mode == .default)
          configurations.append(options)
        },
        setActive: { active, _ in activations.append(active) })
      session.reapplyConfiguration(mixWithOthers: true, isCarPlayConnected: false)
      session.reapplyConfiguration(mixWithOthers: true, isCarPlayConnected: true)
      #expect(configurations == [[.mixWithOthers], []])
      #expect(activations.isEmpty)
      session.reactivateForForeground(
        mixWithOthers: false, isCarPlayConnected: false, isPlaying: false)
      #expect(activations.isEmpty)
      session.setupForPlayback(mixWithOthers: true, isCarPlayConnected: true)
      #expect(configurations.last == [])
      #expect(activations == [true])
    }

    /// A play during an interruption supersedes it, so its end can't resume
    /// playback over a pause made after that play.
    @Test func playDuringInterruptionClearsTheResume() async {
      _ = makeSounds()
      audioManager.wasPlayingWhenInterrupted = true

      audioManager.setGlobalPlaybackState(true)
      #expect(!audioManager.wasPlayingWhenInterrupted)
      audioManager.setGlobalPlaybackState(false)
    }
  #endif
  @Test func quickMixWidgetVolumeClampsPublishesAndKeepsPlaybackPaused() async {
    let (a, b) = makeSounds()
    let originalNames = GlobalSettings.shared.quickMixSoundFileNames
    defer { GlobalSettings.shared.setQuickMixSoundFileNames(originalNames) }
    GlobalSettings.shared.setQuickMixSoundFileNames([a.fileName, b.fileName])
    let saved = preset("Before Quick Mix", selecting: [a.fileName], from: [a, b])
    await install([saved])
    let savedStates = saved.soundStates
    audioManager.enterQuickMix(with: [a])
    audioManager.setGlobalPlaybackState(false)
    a.volume = 0.98
    audioManager.adjustQuickMixSoundVolume(fileName: a.fileName, deltaPercent: 5)
    #expect(a.volume == 1)
    audioManager.adjustQuickMixSoundVolume(fileName: a.fileName, deltaPercent: -5)
    #expect(a.volume == 0.95)
    #expect(
      WidgetStateStore.current().quickMixSounds.first { $0.fileName == a.fileName }?.volume == 0.95)
    #expect(!audioManager.isGloballyPlaying)
    #expect(audioManager.isQuickMix)
    a.volume = 0.02
    audioManager.adjustQuickMixSoundVolume(fileName: a.fileName, deltaPercent: -5)
    #expect(a.volume == 0)
    #expect(b.volume == 0.8)
    #expect(saved.soundStates == savedStates)
    audioManager.exitQuickMix(restoring: true, resuming: false)
    #expect(a.volume == 0.5)
  }

  @Test func quickMixWidgetVolumeIgnoresAnotherModeOrRemovedSound() async {
    let (a, b) = makeSounds()
    let originalNames = GlobalSettings.shared.quickMixSoundFileNames
    defer { GlobalSettings.shared.setQuickMixSoundFileNames(originalNames) }
    GlobalSettings.shared.setQuickMixSoundFileNames([a.fileName])
    let originalVolume = a.volume
    audioManager.adjustQuickMixSoundVolume(fileName: a.fileName, deltaPercent: 5)
    #expect(a.volume == originalVolume)
    audioManager.enterQuickMix(with: [a])
    let otherVolume = b.volume
    audioManager.adjustQuickMixSoundVolume(fileName: b.fileName, deltaPercent: -5)
    #expect(b.volume == otherVolume)
    GlobalSettings.shared.setQuickMixSoundFileNames([])
    audioManager.adjustQuickMixSoundVolume(fileName: a.fileName, deltaPercent: -5)
    #expect(a.volume == 0.8)
    audioManager.exitQuickMix(restoring: true, resuming: false)
  }

}
