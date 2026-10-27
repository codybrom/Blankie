//
//  NowPlayingManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import MediaPlayer
import Observation
import SwiftUI
import os

#if os(iOS)
  import UIKit
#endif

/// The MediaPlayer (`MPNowPlayingInfoCenter`) Now Playing backend, used below OS 27.
@MainActor
final class NowPlayingManager: NowPlayingPublishing {
  var nowPlayingInfo: [String: Any] = [:]

  /// The remote-command actions installed by `AudioManager`, invoked by the
  /// `MPRemoteCommandCenter` targets.
  var remoteCommandHandlers: RemoteCommandHandlers?

  private var isSetup = false
  var currentArtworkId: UUID?
  var currentStaticArtworkPath: String?
  nonisolated(unsafe) var staticArtworkTask: Task<Void, Never>?
  #if os(iOS)
    var currentAnimatedLoopPath: String?
    var currentAnimatedPreviewPath: String?
    let animatedArtworkResolver = AnimatedArtworkResolver()
  #endif
  nonisolated(unsafe) private var updateTimer: Timer?
  // Republishes elapsed time so the system scrubber (lock screen and CarPlay)
  // snaps back to the start each time the longest sound loops.
  nonisolated(unsafe) private var progressTimer: Timer?
  // Last anchored elapsed/duration. The system extrapolates between writes, so
  // re-anchor only on a loop wrap or a duration change (every tick makes the bar
  // stutter). A negative `lastObservedElapsed` forces the next tick to anchor.
  private var lastObservedElapsed: TimeInterval = -1
  private var lastObservedDuration: TimeInterval = 0
  nonisolated(unsafe) private var timerActiveObservation: Task<Void, Never>?
  nonisolated(unsafe) private var lockScreenBgObservation: Task<Void, Never>?
  private var lastPresetId: UUID?  // Track last preset to avoid unnecessary artwork updates
  private var lastSoloSoundId: UUID?  // Track last solo sound so its icon artwork refreshes
  // Set when artwork changed without a preset/solo change (an animation pack
  // finished downloading), so the next update rebuilds and publishes it in full.
  var needsArtworkRebuild = false
  /// The drawn fallback's glyph while it's the artwork, so a later selection
  /// change can redraw it. Nil while other artwork shows.
  var shownFallbackGlyph: FallbackArtwork.Glyph?

  init() {
    // Republish the lock-screen background when the user toggles the setting.
    lockScreenBgObservation = Task { [weak self] in
      for await _ in Observations({ GlobalSettings.shared.lockScreenBackgroundEnabled }) {
        self?.republishCurrentPreset()
      }
    }

    // Refresh the "N Minute Timer" album line when a sleep timer starts or ends.
    // Tracks only `isTimerActive`, so the 1 Hz remainingTime tick never fires it.
    timerActiveObservation = Task { [weak self] in
      for await _ in Observations({ TimerManager.shared.isTimerActive }) {
        self?.republishCurrentPreset()
      }
    }

    #if os(iOS)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(animatedArtworkConditionChanged),
        name: UIAccessibility.reduceMotionStatusDidChangeNotification,
        object: nil
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(animatedArtworkConditionChanged),
        name: Notification.Name.NSProcessInfoPowerStateDidChange,
        object: nil
      )
    #endif
  }

  deinit {
    staticArtworkTask?.cancel()
    updateTimer?.invalidate()
    progressTimer?.invalidate()
    timerActiveObservation?.cancel()
    lockScreenBgObservation?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  private func setupNowPlaying() {
    guard !isSetup else { return }
    Logger.nowPlaying.debug("NowPlayingManager: Setting up Now Playing info")
    isSetup = true

    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    if let artwork = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
  }

  func publishInfo(
    preset: Preset?,
    presetName: String?,
    creatorName: String?,
    artworkId: UUID?,
    isPlaying: Bool
  ) {
    // Coalesce bursts of updates into one publish (0.1 s debounce).
    updateTimer?.invalidate()
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
      Task { @MainActor in
        await self?.performNowPlayingUpdate(
          preset: preset, presetName: presetName, creatorName: creatorName, artworkId: artworkId,
          isPlaying: isPlaying
        )
      }
    }
  }

  private func performNowPlayingUpdate(
    preset: Preset?,
    presetName: String?,
    creatorName: String?,
    artworkId: UUID?,
    isPlaying: Bool
  ) async {
    // Hold all publishing while a pause fade-out still renders: any write reasserts
    // "playing" (iOS derives it from live engine I/O). The engine-idle pause
    // republishes once output is silent.
    if !isPlaying, AudioEngineManager.shared.engine.isRunning {
      stopProgressUpdates()
      return
    }

    setupNowPlaying()

    let resolvedPresetName = preset?.name ?? presetName
    let resolvedCreatorName = preset?.creatorName ?? creatorName

    let displayInfo = NowPlayingDisplay.getDisplayInfo(
      presetName: resolvedPresetName, creatorName: resolvedCreatorName, preset: preset)
    Logger.nowPlaying.debug(
      "NowPlayingManager: Updating Now Playing info with title: \(displayInfo.title), artist: \(displayInfo.artist)"
    )

    // `preset` is the last active preset, which solo mode and Quick Mix don't clear.
    // Skip its thumbnail and accent while either is active.
    let isSoloActive = AudioManager.shared.soloModeSound != nil
    let presetIsOverridden = isSoloActive || AudioManager.shared.isQuickMix
    // Any non-default preset gets a key, artwork or not: the cache also covers
    // animated-only presets, and the widget falls back to the icon (as `display(for:)`).
    let widgetThumbnailKey =
      presetIsOverridden
      ? nil : preset.flatMap { $0.isDefault ? nil : "preset_thumb_\($0.id.uuidString)" }
    let widgetSubtitle = NowPlayingDisplay.widgetSubtitle(
      resolvedCreatorName: resolvedCreatorName)
    AudioManager.shared.publishWidgetSnapshot(
      title: displayInfo.title, subtitle: widgetSubtitle, isPlaying: isPlaying,
      thumbnailKey: widgetThumbnailKey,
      accentColorName: presetIsOverridden ? nil : preset?.accentColorName)

    // Artwork rebuilds when the preset or the solo sound changes. Solo sounds have
    // no preset, so a switch between solo sounds shows up only in the solo id.
    let soloSoundId = AudioManager.shared.soloModeSound?.id
    let presetChanged = preset?.id != lastPresetId
    let soloChanged = soloSoundId != lastSoloSoundId

    updateBasicInfo(displayInfo: displayInfo)
    updateAlbumAndDuration(creatorName: resolvedCreatorName)
    updatePlaybackRate(isPlaying: isPlaying)

    // Touch artwork only on those changes so incremental updates don't restart
    // animated artwork.
    if presetChanged || soloChanged || needsArtworkRebuild {
      needsArtworkRebuild = false
      if let soloSound = AudioManager.shared.soloModeSound {
        // Solo mode: show the sound's own icon, not the last preset's artwork.
        applySoloArtwork(for: soloSound)
        #if os(iOS)
          removeAnimatedArtwork()
        #endif
      } else {
        // Presets without a lock screen background inherit the app-wide default
        // (then the Blankie icon). Applied to a copy so it's never saved to the preset.
        var effectivePreset = preset
        if effectivePreset != nil, effectivePreset?.animatedArtwork == nil {
          effectivePreset?.animatedArtwork = GlobalSettings.shared.defaultLockScreenArtwork
        } else if effectivePreset == nil, AudioManager.shared.isQuickMix,
          let defaultArtwork = GlobalSettings.shared.defaultLockScreenArtwork
        {
          // Quick Mix has no preset, so carry the default lock screen animation on a
          // throwaway preset.
          effectivePreset = Preset(
            id: UUID(),
            name: "Quick Mix",
            soundStates: [],
            isDefault: false,
            createdVersion: nil,
            animatedArtwork: defaultArtwork
          )
        }
        // Load static artwork synchronously so there's one publish; an async load
        // would publish again and restart animated artwork.
        await loadStaticArtworkSync(from: effectivePreset, fallbackArtworkId: artworkId)
        #if os(iOS)
          updateAnimatedArtwork(for: effectivePreset)
        #endif
      }
      lastPresetId = preset?.id
      lastSoloSoundId = soloSoundId

      // One full publish, after both artworks are ready.
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    } else {
      // Incremental update: keep the published artwork objects so animated artwork
      // doesn't restart.
      let center = MPNowPlayingInfoCenter.default()
      let redrewFallback = redrawFallbackIfStale()

      if var updated = center.nowPlayingInfo {
        Logger.nowPlaying.debug(
          "NowPlayingManager: Incremental update (preserving animated artwork)")
        // Merge the non-artwork keys and publish once. Each in-place key write is a
        // full publish, and early ones carry a stale rate ("playing" after a pause).
        for key in [
          MPMediaItemPropertyTitle,
          MPMediaItemPropertyArtist,
          MPMediaItemPropertyAlbumTitle,
          MPNowPlayingInfoPropertyPlaybackRate,
          MPMediaItemPropertyPlaybackDuration,
          MPNowPlayingInfoPropertyElapsedPlaybackTime,
        ] + (redrewFallback ? [MPMediaItemPropertyArtwork] : []) {
          updated[key] = nowPlayingInfo[key]
        }
        center.nowPlayingInfo = updated
      } else {
        // iOS cleared the info, so publish in full.
        Logger.nowPlaying.debug("NowPlayingManager: Full update (iOS cleared nowPlayingInfo)")
        center.nowPlayingInfo = nowPlayingInfo
      }
    }

    // Keep the scrubber tracking the looping sounds only while playing.
    if isPlaying {
      startProgressUpdates()
    } else {
      stopProgressUpdates()
    }
  }

  /// Sets the lock-screen artwork to the soloed sound's rendered icon. Clears
  /// the cached preset-artwork identity so returning to a preset reloads it.
  private func applySoloArtwork(for sound: Sound) {
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    shownFallbackGlyph = nil
    if let artwork = soloArtwork(for: sound) {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    } else if let fallback = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = fallback
    }
  }

  private func updateBasicInfo(displayInfo: (title: String, artist: String)) {
    nowPlayingInfo[MPMediaItemPropertyTitle] = displayInfo.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = displayInfo.artist
  }

  private func updateAlbumAndDuration(creatorName: String?) {
    if let soloSound = AudioManager.shared.soloModeSound {
      updateSoloModeInfo(soloSound: soloSound)
    } else {
      updatePresetModeInfo(creatorName: creatorName)
    }
    // A running timer takes over the album line ("20 Minute Timer") in every mode.
    if TimerManager.shared.isTimerActive {
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = NowPlayingDisplay.timerAlbumLabel()
    }
  }

  private func updateSoloModeInfo(soloSound: Sound) {
    if soloSound.isCustom, soloSound.creditedAuthor != nil {
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie"
    } else {
      nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
    }
    applyProgressAnchorToInfo()
  }

  private func updatePresetModeInfo(creatorName: String?) {
    updateAlbumTitle(creatorName: creatorName)
    updateDurationFromPlayingSounds()
  }

  private func updateAlbumTitle(creatorName: String?) {
    // Without a creator the artist line already lists the sounds (or
    // "Blankie"), so an extra album line is redundant.
    guard creatorName != nil else {
      nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
      return
    }
    // Same preset-ordered, switched-on list as the artist line.
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = NowPlayingDisplay.soundNameSummary(
      NowPlayingDisplay.currentMixSoundTitles())
  }

  private func updateDurationFromPlayingSounds() {
    applyProgressAnchorToInfo()
  }

  /// Writes the current progress anchor into the local `nowPlayingInfo` snapshot
  /// (falling back to indeterminate). Used by the initial publish; the periodic
  /// tick re-anchors the live center afterward.
  private func applyProgressAnchorToInfo() {
    if let anchor = NowPlayingDisplay.currentProgressAnchor() {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = anchor.duration
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = anchor.elapsed
    } else {
      setInfiniteDuration()
    }
  }

  private func setInfiniteDuration() {
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
  }

  private func updatePlaybackRate(isPlaying: Bool) {
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
  }

  func republishCurrentPreset() {
    let preset = PresetManager.shared.currentPreset
    updateInfo(
      preset: preset,
      presetName: preset?.name,
      creatorName: preset?.creatorName,
      artworkId: preset?.artworkId,
      isPlaying: AudioManager.shared.isGloballyPlaying
    )
  }

  /// Forces a full refresh, including artwork (for artwork changes on the same preset).
  func forceRefresh(
    preset: Preset,
    isPlaying: Bool
  ) {
    lastPresetId = nil  // Clear cache to force full artwork update
    // A nil id alone matches Quick Mix's identity, so flag the rebuild too.
    needsArtworkRebuild = true
    updateInfo(
      preset: preset,
      presetName: preset.name,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId,
      isPlaying: isPlaying
    )
  }

  func updatePlaybackState(isPlaying: Bool) {
    setupNowPlaying()

    if nowPlayingInfo.isEmpty {
      nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
      nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0  // Indeterminate

    Logger.nowPlaying.debug(
      "NowPlayingManager: Updating now playing state to \(isPlaying), playbackRate: \(self.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

    if isPlaying {
      startProgressUpdates()
    } else {
      stopProgressUpdates()
    }
  }

  func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
    guard !nowPlayingInfo.isEmpty else { return }

    let isPlaying = AudioManager.shared.isGloballyPlaying

    // Keep our local snapshot in sync so the next full publish is correct.
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    let center = MPNowPlayingInfoCenter.default()
    if center.nowPlayingInfo != nil {
      // Write only the timing and rate keys in place. Replacing the whole dictionary
      // (with its artwork objects) restarts animated lock-screen artwork.
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
      center.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = duration
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    } else {
      // iOS cleared it, so republish info and artwork in full.
      center.nowPlayingInfo = nowPlayingInfo
    }
  }

  /// Watches the active progress source (sleep timer or looping sound) and
  /// re-anchors the scrubber when it wraps or its duration changes. The system
  /// extrapolates from `playbackRate` between writes, so fewer writes keep it smooth.
  private func startProgressUpdates() {
    stopProgressUpdates()
    lastObservedElapsed = -1  // Force the first tick to anchor.
    publishProgressTick()  // Anchor immediately so the bar doesn't lag.

    // Poll faster than we publish: reading `currentTime` is cheap and a tighter
    // poll detects the wrap sooner, so the snap-back is crisp.
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.publishProgressTick()
      }
    }
    // Track during scrolling/interaction too.
    RunLoop.main.add(timer, forMode: .common)
    progressTimer = timer
  }

  private func stopProgressUpdates() {
    progressTimer?.invalidate()
    progressTimer = nil
    lastObservedElapsed = -1
    lastObservedDuration = 0
  }

  /// Re-anchors the system scrubber only on the first tick, a loop wrap, a duration
  /// change, or each whole second of a sleep timer.
  private func publishProgressTick() {
    guard AudioManager.shared.isGloballyPlaying else {
      stopProgressUpdates()
      return
    }

    guard let anchor = NowPlayingDisplay.currentProgressAnchor() else { return }
    let elapsed = anchor.elapsed
    let duration = anchor.duration
    defer {
      lastObservedElapsed = elapsed
      lastObservedDuration = duration
    }

    let isFirst = lastObservedElapsed < 0
    let wrapped = elapsed < lastObservedElapsed - 0.5  // sound loop restarted
    // Each source's duration is an exact constant, so any change means a new source.
    let durationChanged = abs(duration - lastObservedDuration) > 0.001
    // CarPlay extrapolates a sleep timer's bar unreliably, so re-anchor each whole
    // second (timing keys only, in place; artwork untouched).
    let timerAdvanced =
      TimerManager.shared.isTimerActive && floor(elapsed) > floor(lastObservedElapsed)
    guard isFirst || wrapped || durationChanged || timerAdvanced else { return }

    updateProgress(currentTime: elapsed, duration: duration)
  }

  func clear() {
    stopProgressUpdates()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    staticArtworkTask?.cancel()
    staticArtworkTask = nil
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    lastPresetId = nil
    lastSoloSoundId = nil
    shownFallbackGlyph = nil
    #if os(iOS)
      removeAnimatedArtwork()
    #endif
  }
}
