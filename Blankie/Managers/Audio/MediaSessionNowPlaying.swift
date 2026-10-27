//
//  MediaSessionNowPlaying.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 Now Playing backend: resolves what to show, hands it to the
//  observable session model, and keeps one MediaSession published.

#if canImport(NowPlaying)
  import Foundation
  import NowPlaying
  import Observation
  import os

  #if os(iOS)
    import UIKit
  #endif

  @available(iOS 27, macOS 27, visionOS 27, *)
  @MainActor
  final class MediaSessionNowPlaying: NowPlayingPublishing {
    let model = NowPlayingSessionModel()
    private var session: MediaSession<NowPlayingSessionModel>?
    private var primaryRequest: Task<Void, Never>?
    /// The publish waiting out the debounce. The newest call replaces it.
    private var pendingPublish: PendingPublish?
    private var publishDebounce: Task<Void, Never>?
    private var timerActiveObservation: Task<Void, Never>?
    private var timerDurationObservation: Task<Void, Never>?
    private var lockScreenBgObservation: Task<Void, Never>?
    private var continuousObservation: Task<Void, Never>?
    private var loopProgressTimer: Timer?
    private var lastLoopElapsed: TimeInterval?
    private var lastLoopDuration: TimeInterval?
    /// Last preset and single sound the artwork was built for. The system caches
    /// artwork by id, and rebuilding on every publish would restart the animated loop.
    var lastPresetId: UUID?
    var lastSingleSoundId: UUID?
    /// Forces the first artwork build: both ids start nil, which is also Quick Mix's
    /// identity (no preset).
    var hasBuiltArtwork = false
    /// The last good fallback render, keyed by its artwork id, for when a render
    /// fails. Only the current id is ever read, so it holds one entry.
    var fallbackArtworkCache: [String: Data] = [:]
    #if os(iOS)
      var currentAnimatedLoopPath: String?
      var currentAnimatedPreviewPath: String?
      let animatedArtworkResolver = AnimatedArtworkResolver()
      private var reduceMotionObservation: Task<Void, Never>?
      private var powerStateObservation: Task<Void, Never>?
    #endif

    init() {
      // Re-anchor the scrubber when a sleep timer starts, ends or is extended.
      // Tracking only these properties keeps the 1 Hz remainingTime tick out.
      timerActiveObservation = Task { [weak self] in
        for await _ in Observations({ TimerManager.shared.isTimerActive }) {
          self?.refreshTiming()
        }
      }
      timerDurationObservation = Task { [weak self] in
        for await _ in Observations({ TimerManager.shared.selectedDuration }) {
          self?.refreshTiming()
        }
      }

      continuousObservation = Task { [weak self] in
        for await _ in Observations({ GlobalSettings.shared.showPlaybackAsContinuous }) {
          self?.refreshTiming()
        }
      }

      // Republish the lock-screen background when the user toggles the setting.
      lockScreenBgObservation = Task { [weak self] in
        for await _ in Observations({ GlobalSettings.shared.lockScreenBackgroundEnabled }) {
          self?.republishForArtworkGateChange()
        }
      }

      #if os(iOS)
        // Reduce Motion and Low Power Mode each suppress the animated
        // background, so republish whenever either flips.
        reduceMotionObservation = Task { [weak self] in
          for await _ in NotificationCenter.default.notifications(
            named: UIAccessibility.reduceMotionStatusDidChangeNotification)
          {
            self?.republishForArtworkGateChange()
          }
        }
        powerStateObservation = Task { [weak self] in
          for await _ in NotificationCenter.default.notifications(
            named: Notification.Name.NSProcessInfoPowerStateDidChange)
          {
            self?.republishForArtworkGateChange()
          }
        }
      #endif
    }

    isolated deinit {
      primaryRequest?.cancel()
      publishDebounce?.cancel()
      timerActiveObservation?.cancel()
      timerDurationObservation?.cancel()
      lockScreenBgObservation?.cancel()
      continuousObservation?.cancel()
      loopProgressTimer?.invalidate()
      #if os(iOS)
        reduceMotionObservation?.cancel()
        powerStateObservation?.cancel()
      #endif
    }

    func publishInfo(
      preset: Preset?,
      presetName: String?,
      creatorName: String?,
      artworkId: UUID?,
      isPlaying: Bool
    ) {
      // Debounced 0.1 s, like the 26 backend: a preset switch publishes about six
      // times as its sounds settle, and MediaRemote throttles (and drops) that many.
      // Playback state isn't debounced (`updatePlaybackState`), so a pause lands at once.
      pendingPublish = PendingPublish(
        preset: preset, presetName: presetName, creatorName: creatorName,
        artworkId: artworkId, isPlaying: isPlaying)
      publishDebounce?.cancel()
      publishDebounce = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        self?.flushPendingPublish()
      }
    }

    /// Publishes the pending state now, without waiting for the debounce.
    func flushPendingPublish() {
      publishDebounce?.cancel()
      publishDebounce = nil
      guard let pending = pendingPublish else { return }
      pendingPublish = nil
      performPublish(pending)
    }

    private struct PendingPublish {
      let preset: Preset?
      let presetName: String?
      let creatorName: String?
      let artworkId: UUID?
      let isPlaying: Bool
    }

    private func performPublish(_ pending: PendingPublish) {
      let preset = pending.preset
      let isPlaying = pending.isPlaying
      let resolvedPresetName = preset?.name ?? pending.presetName
      let resolvedCreatorName = preset?.creatorName ?? pending.creatorName

      let displayInfo = NowPlayingDisplay.getDisplayInfo(
        presetName: resolvedPresetName, creatorName: resolvedCreatorName, preset: preset)
      Logger.nowPlaying.debug(
        "MediaSessionNowPlaying: publishing title: \(displayInfo.title), subtitle: \(displayInfo.artist)"
      )

      let singleFileName = AudioManager.shared.singleSound?.fileName
      let isQuickMix = AudioManager.shared.isQuickMix
      // Some call sites publish a name without the preset (`exitSingleSound`), and the
      // system reads a changed id as a different item, so preset mode falls back to
      // the current preset. The id, entity and artwork all use this one value.
      let resolvedPreset =
        preset
        ?? (singleFileName == nil && !isQuickMix ? PresetManager.shared.currentPreset : nil)

      model.title = displayInfo.title
      model.subtitle = displayInfo.artist
      model.contentID = NowPlayingSessionMapping.contentID(
        singleFileName: singleFileName, isQuickMix: isQuickMix, presetID: resolvedPreset?.id)
      model.playback = NowPlayingSessionMapping.playback(isPlaying: isPlaying)
      model.entityIdentifiers = entityIdentifiers(for: resolvedPreset)
      refreshTiming()
      refreshArtwork(preset: resolvedPreset, fallbackArtworkId: pending.artworkId)

      publishWidgetSnapshot(
        preset: preset, resolvedCreatorName: resolvedCreatorName, title: displayInfo.title,
        isPlaying: isPlaying)

      publishSessionIfPlaying()
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

    /// Republishes after an artwork gate flips without a preset change, so the
    /// identity check can't skip the rebuild.
    func republishForArtworkGateChange() {
      hasBuiltArtwork = false
      republishCurrentPreset()
    }

    func forceRefresh(preset: Preset, isPlaying: Bool) {
      // Clear the artwork identity so the same preset's new artwork is rebuilt.
      // A nil id alone matches Quick Mix's identity, so also drop the built flag.
      lastPresetId = nil
      lastSingleSoundId = nil
      hasBuiltArtwork = false
      updateInfo(
        preset: preset,
        presetName: preset.name,
        creatorName: preset.creatorName,
        artworkId: preset.artworkId,
        isPlaying: isPlaying
      )
    }

    func updatePlaybackState(isPlaying: Bool) {
      model.playback = NowPlayingSessionMapping.playback(isPlaying: isPlaying)
      refreshTiming()
      publishSessionIfPlaying()
    }

    func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
      guard model.timer == nil else { return }
      model.loopProgress = NowPlayingSessionMapping.loopProgress(
        continuous: GlobalSettings.shared.usesContinuousPlayback,
        elapsed: currentTime, duration: duration, now: .now)
    }

    func clear() {
      // Not terminal: the next publish while playing builds a fresh session.
      primaryRequest?.cancel()
      primaryRequest = nil
      session = nil
      model.title = ""
      model.subtitle = nil
      model.contentID = "default"
      model.playback = .paused
      model.timer = nil
      model.loopProgress = nil
      stopLoopProgressUpdates()
      model.artwork = nil
      #if os(iOS)
        model.animatedArtwork = nil
      #endif
      model.entityIdentifiers = []
      lastPresetId = nil
      lastSingleSoundId = nil
      hasBuiltArtwork = false
      #if os(iOS)
        currentAnimatedLoopPath = nil
        currentAnimatedPreviewPath = nil
      #endif
      // Handlers and navigation state survive a clear. AudioManager installs them
      // once at setup.
    }

    func installRemoteCommands(_ handlers: RemoteCommandHandlers) {
      model.handlers = handlers
    }

    func setNavigationCommandsEnabled(_ enabled: Bool) {
      model.navigationEnabled = enabled
    }

    private func refreshTiming(forceLoopAnchor: Bool = true) {
      let sleepTimer = TimerManager.shared
      let timer = NowPlayingSessionMapping.timer(
        isActive: sleepTimer.isTimerActive,
        selectedDuration: sleepTimer.selectedDuration,
        remainingTime: sleepTimer.remainingTime,
        now: .now)
      if model.timer != timer { model.timer = timer }

      guard !GlobalSettings.shared.usesContinuousPlayback, timer == nil else {
        model.loopProgress = nil
        stopLoopProgressUpdates()
        return
      }

      let anchor = NowPlayingDisplay.currentProgressAnchor()
      let progress = NowPlayingSessionMapping.loopProgress(
        continuous: false, elapsed: anchor?.elapsed ?? 0, duration: anchor?.duration ?? 0, now: .now
      )
      let wrapped = progress.map { $0.elapsed < (lastLoopElapsed ?? 0) - 0.5 } ?? false
      let durationChanged = progress?.duration != lastLoopDuration
      if forceLoopAnchor || wrapped || durationChanged {
        model.loopProgress = progress
      }
      lastLoopElapsed = progress?.elapsed
      lastLoopDuration = progress?.duration

      if model.playback == .playing {
        startLoopProgressUpdates()
      } else {
        stopLoopProgressUpdates()
      }
    }

    /// The system extrapolates between anchors. Poll to catch loop wraps, but
    /// publish only when the loop wraps or its source/duration changes.
    private func startLoopProgressUpdates() {
      guard loopProgressTimer == nil else { return }
      let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.refreshTiming(forceLoopAnchor: false) }
      }
      RunLoop.main.add(timer, forMode: .common)
      loopProgressTimer = timer
    }

    private func stopLoopProgressUpdates() {
      loopProgressTimer?.invalidate()
      loopProgressTimer = nil
      lastLoopElapsed = nil
      lastLoopDuration = nil
    }

    /// Publishes the widget snapshot. `preset` is the last active preset even during
    /// single sound or Quick Mix, so its thumbnail and accent are skipped while either is active.
    private func publishWidgetSnapshot(
      preset: Preset?, resolvedCreatorName: String?, title: String, isPlaying: Bool
    ) {
      let presetIsOverridden =
        AudioManager.shared.singleSound != nil || AudioManager.shared.isQuickMix
      let widgetThumbnailKey =
        presetIsOverridden
        ? nil : preset.flatMap { $0.isDefault ? nil : "preset_thumb_\($0.id.uuidString)" }
      AudioManager.shared.publishWidgetSnapshot(
        title: title,
        subtitle: NowPlayingDisplay.widgetSubtitle(resolvedCreatorName: resolvedCreatorName),
        isPlaying: isPlaying,
        thumbnailKey: widgetThumbnailKey,
        accentColorName: presetIsOverridden ? nil : preset?.accentColorName)
    }

    /// Claims the Now Playing card once playback starts. Every play path configures the
    /// audio session first (the order Apple asks for before requesting primary). The
    /// session persists through pauses. Only `clear()` drops it.
    private func publishSessionIfPlaying() {
      guard model.playback == .playing, session == nil else { return }
      let session = MediaSession(model)
      self.session = session
      primaryRequest = Task { @MainActor [weak self] in
        do {
          try await session.requestToBecomeApplicationPrimary()
          Logger.nowPlaying.debug("MediaSessionNowPlaying: session is application primary")
        } catch {
          // Drop it so the next playing publish retries (a session that never became
          // primary shows no card), unless `clear()` already replaced it.
          if self?.session === session { self?.session = nil }
          Logger.nowPlaying.error(
            "MediaSessionNowPlaying: requestToBecomeApplicationPrimary failed: \(String(describing: error), privacy: .public)"
          )
        }
      }
    }
  }
#endif
