//
//  AudioSessionManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

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
          debugLog(
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
        debugLog(
          "AudioSessionManager: Audio session activated for playback (mixWithOthers: \(mixWithOthers && !isCarPlayConnected), CarPlay: \(isCarPlayConnected))"
        )
      } catch {
        debugLog("AudioSessionManager: Failed to setup audio session: \(error)")
      }
    }

    func deactivate() {
      // Deactivate audio session when stopping to allow other apps to play
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        debugLog("AudioSessionManager: Audio session deactivated")
      } catch {
        debugLog("AudioSessionManager: Failed to deactivate audio session: \(error)")
      }
    }

    func reactivateForForeground(mixWithOthers: Bool, isPlaying: Bool) {
      // Only configure and activate the audio session if we're actually playing
      guard isPlaying else {
        debugLog("AudioSessionManager: Skipping audio session setup - not playing")
        return
      }

      do {
        if mixWithOthers {
          // Use manual volume control when mixing
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          debugLog(
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
        debugLog("AudioSessionManager: Audio session reactivated for foreground")
      } catch {
        debugLog("AudioSessionManager: Failed to reactivate audio session: \(error)")
      }
    }
  }
#endif
