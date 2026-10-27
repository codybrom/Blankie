//
//  MediaSessionNowPlayingTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 Now Playing backend's model: content identity, artwork rebuilds, clear() and
//  sleep-timer timing. Serialized: deinit restores every touched singleton value.
//

#if canImport(NowPlaying)
  import Foundation
  import Testing

  @testable import Blankie

  @Suite(.serialized) @MainActor final class MediaSessionNowPlayingTests {
    private let audioManager = AudioManager.shared
    private let originalAutoPlay: Bool
    private let originalSounds: [Sound]
    private let originalSolo: Sound?
    private let originalQuickMix: Bool
    private let originalCurrentPreset: Preset?
    private let originalDefaultArtwork: AnimatedArtworkRef?
    private let originalContinuous: Bool
    nonisolated private static let testName = "test-rain"

    init() {
      originalContinuous = GlobalSettings.shared.showPlaybackAsContinuous
      GlobalSettings.shared.showPlaybackAsContinuous = true
      originalAutoPlay = GlobalSettings.shared.autoPlayOnLaunch
      originalSounds = audioManager.sounds
      originalSolo = audioManager.soloModeSound
      originalQuickMix = audioManager.isQuickMix
      originalCurrentPreset = PresetManager.shared.currentPreset
      originalDefaultArtwork = GlobalSettings.shared.defaultLockScreenArtwork
      GlobalSettings.shared.setAutoPlayOnLaunch(false)
      // Skips `resetSounds()`: its debounced volume save would land after this suite ends
      // and race the next suite.
      audioManager.soloModeSound = nil
      audioManager.isQuickMix = false
      // With no app-wide animation, an artwork-less preset gets the drawn fallback, whose
      // id includes the accent.
      GlobalSettings.shared.setDefaultLockScreenArtwork(nil)
    }

    isolated deinit {
      // No timer runs when the suite starts, so stopping it is the restore.
      TimerManager.shared.stopTimer()
      GlobalSettings.shared.showPlaybackAsContinuous = originalContinuous
      audioManager.soloModeSound = originalSolo
      audioManager.isQuickMix = originalQuickMix
      audioManager.sounds = originalSounds
      PresetManager.shared.setCurrentPreset(originalCurrentPreset)
      GlobalSettings.shared.setDefaultLockScreenArtwork(originalDefaultArtwork)
      GlobalSettings.shared.setAutoPlayOnLaunch(originalAutoPlay)
      UserDefaults.shared.removeObject(forKey: "\(Self.testName)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(Self.testName)_volume")
    }

    /// A preset with no artwork of its own, made current so the backend's
    /// accent and fallback reads resolve against it.
    private func makeCurrentPreset(id: UUID = UUID(), accentColorName: String = "blue") -> Preset {
      let preset = PresetFactory.makePreset(id: id, accentColorName: accentColorName)
      PresetManager.shared.setCurrentPreset(preset)
      return preset
    }

    // MARK: - Publishing

    /// Publishes debounce 0.1 s. The tests flush because the host's main actor doesn't
    /// reliably run other tasks while a test sleeps.
    @Test func publishesLandOnceAsTheirLastState() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let first = PresetFactory.makePreset(accentColorName: "blue")
      let second = makeCurrentPreset()

      backend.updateInfo(preset: first, presetName: first.name, isPlaying: false)
      backend.updateInfo(preset: second, presetName: second.name, isPlaying: false)
      #expect(backend.model.contentID == "default")
      #expect(backend.model.title.isEmpty)

      backend.flushPendingPublish()
      #expect(backend.model.contentID == "preset:\(second.id.uuidString)")
      #expect(backend.model.title == second.name)

      // Flushed once: a second flush has nothing left to publish.
      backend.updateInfo(preset: first, presetName: first.name, isPlaying: false)
      backend.flushPendingPublish()
      backend.flushPendingPublish()
      #expect(backend.model.contentID == "preset:\(first.id.uuidString)")
    }

    // MARK: - Content identity

    /// `exitSoloMode` publishes a name with no preset; the system reads a
    /// changed id as a different item, so the current preset has to stand in.
    @Test func presetContentIDSurvivesANameOnlyPublish() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")
    }

    @Test func soloedSoundOwnsTheContentID() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      _ = makeCurrentPreset()
      let rain = TestSound(fileName: Self.testName)
      audioManager.sounds = [rain]
      audioManager.soloModeSound = rain

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.contentID == "solo:\(Self.testName)")
    }

    // MARK: - Artwork

    /// Both artwork ids start nil, which is also a valid identity, so the first pass is forced.
    @Test func firstPublishWithoutAPresetStillBuildsArtwork() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      PresetManager.shared.setCurrentPreset(nil)

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.artwork != nil)
    }

    /// With no stored row for the id, the drawn fallback publishes in the same pass as the
    /// title. The system doesn't re-read a bare item.
    @Test func presetWithStoredArtworkIDPublishesArtworkSynchronously() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      var preset = PresetFactory.makePreset(accentColorName: "blue")
      preset.artworkId = UUID()
      PresetManager.shared.setCurrentPreset(preset)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.artwork != nil)
      #expect(backend.model.artwork?.id.hasPrefix("fallback:") == true)
    }

    /// The drawn fallback is a montage of the selected sounds, so it changes with the selection.
    @Test func fallbackArtworkFollowsTheSelectionWithinAPreset() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let rain = TestSound(fileName: Self.testName)
      audioManager.sounds = [rain]
      let preset = makeCurrentPreset()

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      let before = backend.model.artwork?.id
      #expect(before?.hasPrefix("fallback:") == true)

      rain.isSelected = true
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      let after = backend.model.artwork?.id
      #expect(after?.hasPrefix("fallback:") == true)
      #expect(after != before)
      // Only the last good render is kept for a failed one to fall back on.
      #expect(backend.fallbackArtworkCache.count == 1)
    }

    #if os(iOS)
      /// A preset's own still beats the preview of the app-wide default animation
      /// it inherits for the lock screen; without one, the inherited preview wins.
      @Test func ownStillBeatsTheInheritedDefaultAnimation() throws {
        guard #available(iOS 27, *) else { return }
        guard let defaultLoop = BundledAnimatedLoop.allCases.first else { return }
        GlobalSettings.shared.setDefaultLockScreenArtwork(
          AnimatedArtworkRef(source: .bundled, bundledIdentifier: defaultLoop.id))
        let stillPath = "test-still-\(UUID().uuidString).jpg"
        _ = try AnimatedArtworkFileStore.writeData(Data([0xFF, 0xD8, 0xFF, 0xD9]), to: stillPath)
        defer { AnimatedArtworkFileStore.removeItemIfExists(relativePath: stillPath) }

        var preset = PresetFactory.makePreset(accentColorName: "blue")
        preset.artworkId = nil
        preset.animatedArtwork = nil
        preset.staticArtworkPath = stillPath
        PresetManager.shared.setCurrentPreset(preset)
        let withOwnStill = MediaSessionNowPlaying()
        withOwnStill.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
        withOwnStill.flushPendingPublish()
        #expect(withOwnStill.model.artwork?.id == "static:\(stillPath)")

        preset.staticArtworkPath = nil
        PresetManager.shared.setCurrentPreset(preset)
        let inheriting = MediaSessionNowPlaying()
        inheriting.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
        inheriting.flushPendingPublish()
        #expect(inheriting.model.artwork?.id == "bundled:\(defaultLoop.id)")
      }
    #endif

    /// Rebuilding artwork restarts the animated loop, so only a new accent (the fallback's
    /// color) changes the id.
    @Test func artworkIDHoldsUntilTheAccentChanges() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset(accentColorName: "blue")

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      let firstID = backend.model.artwork?.id
      #expect(firstID != nil)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.artwork?.id == firstID)

      let recolored = makeCurrentPreset(id: preset.id, accentColorName: "red")
      backend.forceRefresh(preset: recolored, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.artwork?.id != firstID)
    }

    // MARK: - Clearing

    @Test func clearEmptiesTheCardAndTheNextPublishRefillsIt() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()

      backend.clear()
      #expect(backend.model.title.isEmpty)
      #expect(backend.model.contentID == "default")
      #expect(backend.model.content?.artwork == nil)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.title == preset.name)
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")
    }

    @Test func continuousPreferenceSwitchesThePublishedLoopAndPlayerProgress() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let sound = TestSound(fileName: Self.testName)
      sound.stubbedDuration = 120
      sound.isSelected = true
      audioManager.sounds = [sound]
      audioManager.soloModeSound = sound
      let backend = MediaSessionNowPlaying()
      backend.updateInfo(isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.loopProgress == nil)
      #expect(!GlobalSettings.shared.showsPlaybackProgress(timerActive: false))

      GlobalSettings.shared.showPlaybackAsContinuous = false
      backend.updatePlaybackState(isPlaying: false)
      #expect(backend.model.loopProgress?.duration == 120)
      #expect(backend.model.content?.id == "solo:\(Self.testName):loop:120.0")
      #expect(GlobalSettings.shared.showsPlaybackProgress(timerActive: false))
      #expect(backend.model.playback == .paused)

      TimerManager.shared.startTimer(duration: 600)
      backend.updatePlaybackState(isPlaying: false)
      #expect(backend.model.timer?.duration == 600)
      #expect(backend.model.loopProgress == nil)
      #expect(backend.model.content?.id == "solo:\(Self.testName):timed:600")
      GlobalSettings.shared.showPlaybackAsContinuous = true
      backend.updatePlaybackState(isPlaying: false)
      #expect(backend.model.timer?.duration == 600)
      #expect(GlobalSettings.shared.showsPlaybackProgress(timerActive: true))

      TimerManager.shared.stopTimer()
      backend.updatePlaybackState(isPlaying: false)
      #expect(backend.model.timer == nil)
      #expect(backend.model.loopProgress == nil)
      #expect(backend.model.content?.id == "solo:\(Self.testName)")
      backend.clear()
    }

    // MARK: - Sleep timer

    /// With continuous playback enabled, only a sleep timer moves the scrubber.
    @Test func timingFollowsTheSleepTimer() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.timer == nil)

      TimerManager.shared.startTimer(duration: 600)
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.timer?.duration == 600)
      // A timed card publishes under its own id so the system re-reads the finite duration.
      #expect(backend.model.content?.id == "\(backend.model.contentID):timed:600")

      // Adding time publishes a new item too, so the card picks up the new end.
      TimerManager.shared.addTime(minutes: 5)
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.timer?.duration == 900)
      #expect(backend.model.content?.id == "\(backend.model.contentID):timed:900")

      TimerManager.shared.stopTimer()
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      backend.flushPendingPublish()
      #expect(backend.model.timer == nil)
      #expect(backend.model.content?.id == backend.model.contentID)
    }
  }
#endif
