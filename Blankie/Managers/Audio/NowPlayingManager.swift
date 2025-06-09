//
//  NowPlayingManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import MediaPlayer
import SwiftUI

/// Manages Now Playing info for media playback controls
final class NowPlayingManager {
  private var nowPlayingInfo: [String: Any] = [:]

  private var isSetup = false

  init() {
    // Don't setup immediately to avoid triggering audio session
  }

  private func setupNowPlaying() {
    guard !isSetup else { return }
    print("🎵 NowPlayingManager: Setting up Now Playing info")
    isSetup = true

    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0  // Start as paused

    if let artwork = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
  }

  func updateInfo(
    presetName: String? = nil, creatorName: String? = nil, artworkData: Data? = nil, isPlaying: Bool
  ) {
    setupNowPlaying()

    let displayInfo = getDisplayInfo(presetName: presetName, creatorName: creatorName)
    print(
      "🎵 NowPlayingManager: Updating Now Playing info with title: \(displayInfo.title), artist: \(displayInfo.artist)"
    )

    updateBasicInfo(displayInfo: displayInfo)
    updateAlbumAndDuration(creatorName: creatorName)
    updatePlaybackRate(isPlaying: isPlaying)
    updateArtwork(artworkData: artworkData)

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
    let playingSounds = AudioManager.shared.sounds.filter { $0.player?.isPlaying == true }
    if !playingSounds.isEmpty {
      let longestSound = playingSounds.max {
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

  private func updateArtwork(artworkData: Data?) {
    print(
      "🎨 NowPlayingManager: Processing artwork data: \(artworkData != nil ? "✅ \(artworkData!.count) bytes" : "❌ None")"
    )
    if let customArtwork = loadCustomArtwork(from: artworkData) {
      print("🎨 NowPlayingManager: ✅ Custom artwork loaded successfully")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = customArtwork
    } else if let defaultArtwork = loadArtwork() {
      print("🎨 NowPlayingManager: Using default artwork")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = defaultArtwork
    } else {
      print("🎨 NowPlayingManager: ❌ No artwork available")
    }
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
    print(
      "🎵 NowPlayingManager: Updating now playing state to \(isPlaying), playbackRate: \(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
    guard !nowPlayingInfo.isEmpty else { return }

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
}
