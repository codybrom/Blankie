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

    private init() {}

    func setupForPlayback(mixWithOthers: Bool, isCarPlayConnected: Bool) {
      do {
        // Force exclusive audio when CarPlay is connected
        // Only setup audio session when we actually start playing
        if mixWithOthers && !isCarPlayConnected {
          // Use manual volume control when mixing
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          Logger.audio.debug(
            "AudioSessionManager: Setting options to [.mixWithOthers] - MANUAL VOLUME CONTROL")

          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: options
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // Exclusive playback
          )
        }

        try AVAudioSession.sharedInstance().setActive(true)
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
      setupForPlayback(mixWithOthers: mixWithOthers, isCarPlayConnected: isCarPlayConnected)
    }

    func deactivate() {
      // Deactivate audio session when stopping to allow other apps to play
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Logger.audio.debug("AudioSessionManager: Audio session deactivated")
      } catch {
        Logger.audio.error(
          "AudioSessionManager: Failed to deactivate audio session: \(error, privacy: .public)")
      }
    }

    func reactivateForForeground(mixWithOthers: Bool, isPlaying: Bool) {
      // Only configure and activate the audio session if we're actually playing
      guard isPlaying else {
        Logger.audio.debug("AudioSessionManager: Skipping audio session setup - not playing")
        return
      }

      do {
        if mixWithOthers {
          // Use manual volume control when mixing
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          Logger.audio.debug(
            "AudioSessionManager: Reactivating with [.mixWithOthers] - MANUAL VOLUME CONTROL")

          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: options
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []
          )
        }

        try AVAudioSession.sharedInstance().setActive(true)
        Logger.audio.debug("AudioSessionManager: Audio session reactivated for foreground")
      } catch {
        Logger.audio.error(
          "AudioSessionManager: Failed to reactivate audio session: \(error, privacy: .public)")
      }
    }
  }
#endif
