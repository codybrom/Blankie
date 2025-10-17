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
  #endif
  private var updateTimer: Timer?
  private var cancellables = Set<AnyCancellable>()

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
    print("🎵 NowPlayingManager: Setting up Now Playing info")
    isSetup = true

    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0 // Start as paused

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
        self?.performNowPlayingUpdate(
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
  ) {
    setupNowPlaying()

    let resolvedPresetName = preset?.name ?? presetName
    let resolvedCreatorName = preset?.creatorName ?? creatorName

    let displayInfo = getDisplayInfo(presetName: resolvedPresetName, creatorName: resolvedCreatorName)
    print(
      "🎵 NowPlayingManager: Updating Now Playing info with title: \(displayInfo.title), artist: \(displayInfo.artist)"
    )

    updateBasicInfo(displayInfo: displayInfo)
    updateAlbumAndDuration(creatorName: resolvedCreatorName)
    updatePlaybackRate(isPlaying: isPlaying)

    loadStaticArtwork(from: preset, fallbackArtworkId: artworkId)
    updateAnimatedArtwork(for: preset)

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

  func updatePlaybackState(isPlaying: Bool) {
    setupNowPlaying() // Ensure setup is done before updating

    // Ensure nowPlayingInfo dictionary exists
    if nowPlayingInfo.isEmpty {
      // Recreate basic info if needed
      nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
      nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    }

    // Update playback state
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0 // Infinite for ambient sounds

    // Update the now playing info
    print(
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
