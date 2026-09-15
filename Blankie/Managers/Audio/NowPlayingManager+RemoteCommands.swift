//
//  NowPlayingManager+RemoteCommands.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The MediaPlayer half of the remote commands: MPRemoteCommandCenter targets
//  that forward to the handlers AudioManager installed.

import MediaPlayer
import os

// MARK: - Remote Commands

extension NowPlayingManager {
  func installRemoteCommands(_ handlers: RemoteCommandHandlers) {
    remoteCommandHandlers = handlers

    let commandCenter = MPRemoteCommandCenter.shared()

    // Enable the commands
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true

    removeExistingCommandHandlers(commandCenter)
    addPlaybackCommandHandlers(commandCenter)
    addNavigationCommandHandlers(commandCenter)
  }

  func setNavigationCommandsEnabled(_ enabled: Bool) {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.nextTrackCommand.isEnabled = enabled
    commandCenter.previousTrackCommand.isEnabled = enabled

    Logger.audio.debug(
      "AudioManager: Next/Previous commands \(enabled ? "enabled" : "disabled")")
  }

  private func removeExistingCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    // Remove all previous handlers
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
  }

  private func addPlaybackCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    commandCenter.playCommand.addTarget { [weak self] _ in
      Logger.audio.debug("AudioManager: Media key play command received")
      Task { @MainActor in
        self?.remoteCommandHandlers?.play()
      }
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      Logger.audio.debug("AudioManager: Media key pause command received")
      Task { @MainActor in
        self?.remoteCommandHandlers?.pause()
      }
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      Logger.audio.debug("AudioManager: Media key toggle command received")
      Task { @MainActor in
        self?.remoteCommandHandlers?.togglePlayPause()
      }
      return .success
    }
  }

  private func addNavigationCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    // Next/Previous track commands for preset navigation
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      Logger.audio.debug("AudioManager: Next track command received")
      guard let handlers = self?.remoteCommandHandlers else { return .commandFailed }

      Task { @MainActor in
        // The status is returned below, before the handler runs, so its answer
        // only matters to backends that can reply asynchronously.
        _ = handlers.next()
      }
      return .success
    }

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      Logger.audio.debug("AudioManager: Previous track command received")
      guard let handlers = self?.remoteCommandHandlers else { return .commandFailed }

      Task { @MainActor in
        _ = handlers.previous()
      }
      return .success
    }
  }
}
