//
//  NowPlayingPublishing.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The Now Playing surface AudioManager publishes through, so the backend can
//  be chosen at startup without the call sites knowing which one they have.

import Foundation

/// The remote-command actions the app supports, built by `AudioManager` and
/// handed to the Now Playing backend to invoke.
struct RemoteCommandHandlers {
  let play: @MainActor () -> Void
  let pause: @MainActor () -> Void
  let togglePlayPause: @MainActor () -> Void
  /// Return `false` only when the command could not be handled.
  let next: @MainActor () -> Bool
  /// Return `false` only when the command could not be handled.
  let previous: @MainActor () -> Bool
}

/// What a Now Playing backend must publish and which remote commands it installs.
@MainActor
protocol NowPlayingPublishing: AnyObject {
  func updateInfo(
    preset: Preset?,
    presetName: String?,
    creatorName: String?,
    artworkId: UUID?,
    isPlaying: Bool
  )
  func republishCurrentPreset()
  func forceRefresh(preset: Preset, isPlaying: Bool)
  func updatePlaybackState(isPlaying: Bool)
  func updateProgress(currentTime: TimeInterval, duration: TimeInterval)
  func clear()
  func installRemoteCommands(_ handlers: RemoteCommandHandlers)
  func setNavigationCommandsEnabled(_ enabled: Bool)
}

extension NowPlayingPublishing {
  /// Defaults for the call sites that publish only some of the fields; forwards
  /// to the conforming backend's implementation.
  func updateInfo(
    preset: Preset? = nil,
    presetName: String? = nil,
    creatorName: String? = nil,
    artworkId: UUID? = nil,
    isPlaying: Bool
  ) {
    updateInfo(
      preset: preset,
      presetName: presetName,
      creatorName: creatorName,
      artworkId: artworkId,
      isPlaying: isPlaying
    )
  }
}
