//
//  NowPlayingManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Manages Now Playing info for media playback controls
@MainActor
final class NowPlayingManager {
  var nowPlayingInfo: [String: Any] = [:]

  private var isSetup = false
  var currentArtworkId: UUID?
  var currentStaticArtworkPath: String?
  var staticArtworkTask: Task<Void, Never>?
  #if os(iOS)
    var currentAnimatedLoopPath: String?
    var currentAnimatedPreviewPath: String?
    // ODR download + Documents-cache tasks in flight, keyed by bundled id.
    // Lets duplicate triggers for the same animated artwork coalesce instead
    // of spawning parallel downloads and cache-copy attempts.
    var animatedArtworkDownloadTasks: [String: Task<Void, Never>] = [:]
  #endif
  private var updateTimer: Timer?
  private var cancellables = Set<AnyCancellable>()
  private var lastPresetId: UUID?  // Track last preset to avoid unnecessary artwork updates

  init() {
    // Don't setup immediately to avoid triggering audio session
    GlobalSettings.shared.$lockScreenBackgroundEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.republishCurrentPreset()
      }
      .store(in: &cancellables)

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
    cancellables.removeAll()
    NotificationCenter.default.removeObserver(self)
  }

  private func setupNowPlaying() {
    guard !isSetup else { return }
    debugLog("🎵 NowPlayingManager: Setting up Now Playing info")
    isSetup = true

    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0  // Start as paused

    if let artwork = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
  }

  func updateInfo(
    preset: Preset? = nil,
    presetName: String? = nil,
    creatorName: String? = nil,
    artworkId: UUID? = nil,
    isPlaying: Bool
  ) {
    // Debounce rapid successive updates during initialization
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
    setupNowPlaying()

    let resolvedPresetName = preset?.name ?? presetName
    let resolvedCreatorName = preset?.creatorName ?? creatorName

    let displayInfo = getDisplayInfo(
      presetName: resolvedPresetName, creatorName: resolvedCreatorName)
    debugLog(
      "🎵 NowPlayingManager: Updating Now Playing info with title: \(displayInfo.title), artist: \(displayInfo.artist)"
    )

    // Check if preset changed to determine if we need full update
    let presetChanged = preset?.id != lastPresetId

    updateBasicInfo(displayInfo: displayInfo)
    updateAlbumAndDuration(creatorName: resolvedCreatorName)
    updatePlaybackRate(isPlaying: isPlaying)

    // Only update artwork when preset changes to avoid restarting animated artwork
    if presetChanged {
      // CRITICAL: Load static artwork synchronously to avoid double-publishing
      // If we load async, the artwork loads after we publish, triggering a second update that restarts animated artwork
      await loadStaticArtworkSync(from: preset, fallbackArtworkId: artworkId)
      updateAnimatedArtwork(for: preset)
      lastPresetId = preset?.id

      // Full update when preset changes (only published once, after both artworks are ready)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    } else {
      // Incremental update - only update specific keys to avoid restarting animated artwork
      // CRITICAL: We update keys in-place on the existing dictionary to preserve artwork objects
      let center = MPNowPlayingInfoCenter.default()

      if center.nowPlayingInfo != nil {
        debugLog("🎵 NowPlayingManager: Incremental update (preserving animated artwork)")
        // Update only non-artwork keys in-place
        center.nowPlayingInfo?[MPMediaItemPropertyTitle] = nowPlayingInfo[MPMediaItemPropertyTitle]
        center.nowPlayingInfo?[MPMediaItemPropertyArtist] =
          nowPlayingInfo[MPMediaItemPropertyArtist]
        center.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] =
          nowPlayingInfo[MPMediaItemPropertyAlbumTitle]
        center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
          nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]
        center.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] =
          nowPlayingInfo[MPMediaItemPropertyPlaybackDuration]
        center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
          nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime]
      } else {
        // No existing info (iOS cleared it), do full update
        debugLog("🎵 NowPlayingManager: Full update (iOS cleared nowPlayingInfo)")
        center.nowPlayingInfo = nowPlayingInfo
      }
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
  }

  private func updateSoloModeInfo(soloSound: Sound) {
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie (Solo Mode)"

    if let player = soloSound.player {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.duration
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
    }
  }

  private func updatePresetModeInfo(creatorName: String?) {
    updateAlbumTitle(creatorName: creatorName)
    updateDurationFromPlayingSounds()
  }

  private func updateAlbumTitle(creatorName: String?) {
    if creatorName != nil {
      let activeSounds = AudioManager.shared.sounds.filter { $0.player?.isPlaying == true }
      if !activeSounds.isEmpty {
        let soundNames = activeSounds.map { $0.title }.joined(separator: ", ")
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = soundNames
      } else {
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie"
      }
    } else {
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie"
    }
  }

  private func updateDurationFromPlayingSounds() {
    // Use active (selected) sounds instead of only playing sounds
    // This ensures we track time even when paused
    let activeSounds = AudioManager.shared.sounds.filter { $0.isSelected }
    if !activeSounds.isEmpty {
      let longestSound = activeSounds.max {
        ($0.player?.duration ?? 0) < ($1.player?.duration ?? 0)
      }
      if let longest = longestSound, let player = longest.player {
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
      } else {
        setInfiniteDuration()
      }
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

  /// Force a full refresh of Now Playing info including artwork
  /// Used when artwork changes on the same preset
  func forceRefresh(
    preset: Preset,
    isPlaying: Bool
  ) {
    lastPresetId = nil  // Clear cache to force full artwork update
    updateInfo(
      preset: preset,
      presetName: preset.name,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId,
      isPlaying: isPlaying
    )
  }

  func updatePlaybackState(isPlaying: Bool) {
    setupNowPlaying()  // Ensure setup is done before updating

    // Ensure nowPlayingInfo dictionary exists
    if nowPlayingInfo.isEmpty {
      // Recreate basic info if needed
      nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
      nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    }

    // Update playback state
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0  // Infinite for ambient sounds

    // Update the now playing info
    debugLog(
      "🎵 NowPlayingManager: Updating now playing state to \(isPlaying), playbackRate: \(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
    guard !nowPlayingInfo.isEmpty else { return }

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration

    // Ensure playback rate reflects current state
    let isPlaying = AudioManager.shared.isGloballyPlaying
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    staticArtworkTask?.cancel()
    staticArtworkTask = nil
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    #if os(iOS)
      removeAnimatedArtwork()
    #endif
  }
}
