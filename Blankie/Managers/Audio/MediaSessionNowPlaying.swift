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

  @available(iOS 27, macOS 27, visionOS 27, *)
  @MainActor
  final class MediaSessionNowPlaying: NowPlayingPublishing {
    private let model = NowPlayingSessionModel()
    private var session: MediaSession<NowPlayingSessionModel>?
    private var timerActiveObservation: Task<Void, Never>?
    private var timerDurationObservation: Task<Void, Never>?

    init() {
      // Re-anchor the scrubber when a sleep timer starts, ends, or is extended.
      // Tracking only these two properties keeps the 1 Hz remainingTime tick
      // from firing the loop. This backend is @MainActor, so the task runs there.
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
    }

    deinit {
      timerActiveObservation?.cancel()
      timerDurationObservation?.cancel()
    }

    func publishInfo(
      preset: Preset?,
      presetName: String?,
      creatorName: String?,
      artworkId: UUID?,
      isPlaying: Bool
    ) {
      let resolvedPresetName = preset?.name ?? presetName
      let resolvedCreatorName = preset?.creatorName ?? creatorName

      let displayInfo = NowPlayingDisplay.getDisplayInfo(
        presetName: resolvedPresetName, creatorName: resolvedCreatorName)
      Logger.nowPlaying.debug(
        "MediaSessionNowPlaying: publishing title: \(displayInfo.title), subtitle: \(displayInfo.artist)"
      )

      model.title = displayInfo.title
      model.subtitle = displayInfo.artist
      model.contentID = NowPlayingSessionMapping.contentID(
        soloFileName: AudioManager.shared.soloModeSound?.fileName,
        isQuickMix: AudioManager.shared.isQuickMix,
        presetID: preset?.id)
      model.playback = NowPlayingSessionMapping.playback(isPlaying: isPlaying)
      refreshTiming()

      publishWidgetSnapshot(
        preset: preset, resolvedCreatorName: resolvedCreatorName, title: displayInfo.title,
        isPlaying: isPlaying)

      ensureSession()
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

    func forceRefresh(preset: Preset, isPlaying: Bool) {
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
    }

    func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
      // No-op: ambient playback publishes a continuous duration on 27, so there
      // is no loop progress to anchor. Only the sleep timer moves the scrubber.
    }

    func clear() {
      session = nil
      model.title = ""
      model.subtitle = nil
      model.contentID = "default"
      model.playback = .paused
      model.timer = nil
      model.artwork = nil
      #if os(iOS)
        model.animatedArtwork = nil
      #endif
      model.entityIdentifiers = []
      // The installed handlers and navigation state survive: AudioManager
      // installs them once at setup, exactly as the 26 backend keeps its
      // command-center targets across a clear.
    }

    func installRemoteCommands(_ handlers: RemoteCommandHandlers) {
      model.handlers = handlers
    }

    func setNavigationCommandsEnabled(_ enabled: Bool) {
      model.navigationEnabled = enabled
    }

    private func refreshTiming() {
      let sleepTimer = TimerManager.shared
      model.timer = NowPlayingSessionMapping.timer(
        isActive: sleepTimer.isTimerActive,
        selectedDuration: sleepTimer.selectedDuration,
        remainingTime: sleepTimer.remainingTime,
        now: .now)
    }

    /// The widget's own snapshot, published on every update. `preset` is the
    /// last active preset even during solo / Quick Mix, so its thumbnail and
    /// accent are suppressed while either overrides the mix.
    private func publishWidgetSnapshot(
      preset: Preset?, resolvedCreatorName: String?, title: String, isPlaying: Bool
    ) {
      let presetIsOverridden =
        AudioManager.shared.soloModeSound != nil || AudioManager.shared.isQuickMix
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

    /// Publishes the session once and keeps it: pausing must not drop the card,
    /// only `clear()` does.
    private func ensureSession() {
      guard session == nil else { return }
      #if os(iOS) || os(visionOS)
        // Apple asks for a configured audio session before requesting primary.
        // Launching with autoplay off never reaches `playSelected()`, so the
        // .playback category isn't set yet when the first publish arrives.
        AudioManager.shared.setupAudioSessionForPlayback()
      #endif
      let session = MediaSession(model)
      self.session = session
      Task { @MainActor in
        do {
          try await session.requestToBecomeApplicationPrimary()
          Logger.nowPlaying.debug("MediaSessionNowPlaying: session is application primary")
        } catch {
          Logger.nowPlaying.error(
            "MediaSessionNowPlaying: requestToBecomeApplicationPrimary failed: \(String(describing: error), privacy: .public)"
          )
        }
      }
    }
  }
#endif
