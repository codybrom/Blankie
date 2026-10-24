//
//  AudioSessionManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import os

#if os(iOS) || os(visionOS)
  import AVFoundation
  import SwiftUI

  /// Manages iOS/visionOS audio session configuration
  final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private let setCategory:
      (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void
    private let setActive: (Bool, AVAudioSession.SetActiveOptions) throws -> Void

    init(
      setCategory:
        @escaping (
          AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions
        ) throws -> Void = {
          try AVAudioSession.sharedInstance().setCategory($0, mode: $1, options: $2)
        },
      setActive: @escaping (Bool, AVAudioSession.SetActiveOptions) throws -> Void = {
        try AVAudioSession.sharedInstance().setActive($0, options: $1)
      }
    ) {
      self.setCategory = setCategory
      self.setActive = setActive
    }

    func setupForPlayback(mixWithOthers: Bool, isCarPlayConnected: Bool) {
      do {
        try configure(mixWithOthers: mixWithOthers, isCarPlayConnected: isCarPlayConnected)
        try setActive(true, [])
        Logger.audio.debug(
          "AudioSessionManager: Audio session activated for playback (mixWithOthers: \(mixWithOthers && !isCarPlayConnected), CarPlay: \(isCarPlayConnected))"
        )
      } catch {
        Logger.audio.error(
          "AudioSessionManager: Failed to setup audio session: \(error, privacy: .public)")
      }
    }

    /// Re-applies category/options/mode after a media-services reset, which
    /// wipes the session configuration (Apple requires a full re-set).
    func reapplyConfiguration(mixWithOthers: Bool, isCarPlayConnected: Bool) {
      do {
        // Rebuilding the session is not a playback request. Stay inactive until
        // the user plays again, so an exclusive session cannot silence another app.
        try configure(mixWithOthers: mixWithOthers, isCarPlayConnected: isCarPlayConnected)
      } catch {
        Logger.audio.error(
          "AudioSessionManager: Failed to restore audio configuration: \(error, privacy: .public)")
      }
    }

    private func configure(mixWithOthers: Bool, isCarPlayConnected: Bool) throws {
      let options: AVAudioSession.CategoryOptions =
        mixWithOthers && !isCarPlayConnected ? [.mixWithOthers] : []
      try setCategory(.playback, .default, options)
    }

    func deactivate() {
      // Deactivate audio session when stopping to allow other apps to play
      do {
        try setActive(false, .notifyOthersOnDeactivation)
        Logger.audio.debug("AudioSessionManager: Audio session deactivated")
      } catch {
        Logger.audio.error(
          "AudioSessionManager: Failed to deactivate audio session: \(error, privacy: .public)")
      }
    }

    func reactivateForForeground(mixWithOthers: Bool, isCarPlayConnected: Bool, isPlaying: Bool) {
      // Only configure and activate the audio session if we're actually playing
      guard isPlaying else {
        Logger.audio.debug("AudioSessionManager: Skipping audio session setup - not playing")
        return
      }

      // Same rules as starting playback, including exclusive audio under CarPlay.
      setupForPlayback(mixWithOthers: mixWithOthers, isCarPlayConnected: isCarPlayConnected)
    }
  }
#endif
