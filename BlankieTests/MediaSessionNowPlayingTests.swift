//
//  MediaSessionNowPlayingTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 backend's published model: content identity, when artwork is
//  rebuilt, the state clear() leaves behind, and sleep-timer timing.
//
//  Serialized + main-actor: drives the AudioManager / PresetManager /
//  GlobalSettings / TimerManager singletons; every touched value is restored in
//  deinit. Every test is a no-op below OS 27, where the backend doesn't exist.
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
    nonisolated private static let testName = "test-rain"

    init() {
      originalAutoPlay = GlobalSettings.shared.autoPlayOnLaunch
      originalSounds = audioManager.sounds
      originalSolo = audioManager.soloModeSound
      originalQuickMix = audioManager.isQuickMix
      originalCurrentPreset = PresetManager.shared.currentPreset
      originalDefaultArtwork = GlobalSettings.shared.defaultLockScreenArtwork
      GlobalSettings.shared.setAutoPlayOnLaunch(false)
      // Not `resetSounds()`: its debounced global-volume save lands on the main
      // run loop after this suite ends and races the migration suite that runs
      // next. Every test sets the sounds, solo and Quick Mix state it needs.
      audioManager.soloModeSound = nil
      audioManager.isQuickMix = false
      // With no app-wide lock screen animation, a preset that carries no artwork
      // of its own lands on the drawn fallback — the one source whose artwork id
      // folds in the accent.
      GlobalSettings.shared.setDefaultLockScreenArtwork(nil)
    }

    isolated deinit {
      // Nothing here starts a timer that outlives its test, so stopping is the
      // restore: the suite never runs with one already counting down.
      TimerManager.shared.stopTimer()
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

    // MARK: - Content identity

    /// `exitSoloMode` publishes a name with no preset; the system reads a
    /// changed id as a different item, so the current preset has to stand in.
    @Test func presetContentIDSurvivesANameOnlyPublish() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")
    }

    /// A soloed sound is its own item, even while a preset is still current.
    @Test func soloedSoundOwnsTheContentID() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      _ = makeCurrentPreset()
      let rain = TestSound(fileName: Self.testName)
      audioManager.sounds = [rain]
      audioManager.soloModeSound = rain

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      #expect(backend.model.contentID == "solo:\(Self.testName)")
    }

    // MARK: - Artwork

    /// Both artwork ids start nil, which is also a valid identity, so the first
    /// pass has to be forced or a card with no preset would never get artwork.
    @Test func firstPublishWithoutAPresetStillBuildsArtwork() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      PresetManager.shared.setCurrentPreset(nil)

      backend.updateInfo(presetName: "Blankie", isPlaying: false)
      #expect(backend.model.artwork != nil)
    }

    /// Stored artwork is decided in the same pass as the title. With no row for
    /// the id, the drawn fallback is published at once instead of leaving the
    /// card bare while a load runs — the system never re-reads a bare item.
    @Test func presetWithStoredArtworkIDPublishesArtworkSynchronously() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      var preset = PresetFactory.makePreset(accentColorName: "blue")
      preset.artworkId = UUID()
      PresetManager.shared.setCurrentPreset(preset)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.artwork != nil)
      #expect(backend.model.artwork?.id.hasPrefix("fallback:") == true)
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
        #expect(withOwnStill.model.artwork?.id == "static:\(stillPath)")

        preset.staticArtworkPath = nil
        PresetManager.shared.setCurrentPreset(preset)
        let inheriting = MediaSessionNowPlaying()
        inheriting.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
        #expect(inheriting.model.artwork?.id == "bundled:\(defaultLoop.id)")
      }
    #endif

    /// Rebuilding artwork restarts the animated loop, so an incremental publish
    /// of the same preset keeps the id; a new accent through `forceRefresh`
    /// changes it, because the drawn fallback renders in that accent.
    @Test func artworkIDHoldsUntilTheAccentChanges() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset(accentColorName: "blue")

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      let firstID = backend.model.artwork?.id
      #expect(firstID != nil)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.artwork?.id == firstID)

      let recolored = makeCurrentPreset(id: preset.id, accentColorName: "red")
      backend.forceRefresh(preset: recolored, isPlaying: false)
      #expect(backend.model.artwork?.id != firstID)
    }

    // MARK: - Clearing

    /// `clear()` is not terminal: it empties the card and the next publish
    /// builds a full one again.
    @Test func clearEmptiesTheCardAndTheNextPublishRefillsIt() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)

      backend.clear()
      #expect(backend.model.title.isEmpty)
      #expect(backend.model.contentID == "default")
      #expect(backend.model.content?.artwork == nil)

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.title == preset.name)
      #expect(backend.model.contentID == "preset:\(preset.id.uuidString)")
    }

    // MARK: - Sleep timer

    /// Only a sleep timer moves the scrubber on 27, so the model carries timing
    /// exactly while one is counting down.
    @Test func timingFollowsTheSleepTimer() {
      guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
      let backend = MediaSessionNowPlaying()
      let preset = makeCurrentPreset()

      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.timer == nil)

      TimerManager.shared.startTimer(duration: 600)
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.timer?.duration == 600)
      // A timed card publishes under its own id so the system re-reads the
      // finite duration instead of keeping the continuous layout.
      #expect(backend.model.content?.id == "\(backend.model.contentID):timed")

      TimerManager.shared.stopTimer()
      backend.updateInfo(preset: preset, presetName: preset.name, isPlaying: false)
      #expect(backend.model.timer == nil)
      #expect(backend.model.content?.id == backend.model.contentID)
    }
  }
#endif
