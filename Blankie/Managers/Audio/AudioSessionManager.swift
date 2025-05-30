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
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers, .duckOthers]
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // Exclusive playback
          )
        }
        try AVAudioSession.sharedInstance().setActive(true)
        print(
          "🎵 AudioSessionManager: Audio session activated for playback (mixWithOthers: \(mixWithOthers && !isCarPlayConnected), CarPlay: \(isCarPlayConnected))"
        )
      } catch {
        print("❌ AudioSessionManager: Failed to setup audio session: \(error)")
      }
    }

    func deactivate() {
      // Deactivate audio session when stopping to allow other apps to play
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("🎵 AudioSessionManager: Audio session deactivated")
      } catch {
        print("❌ AudioSessionManager: Failed to deactivate audio session: \(error)")
      }
    }

    func reactivateForForeground(mixWithOthers: Bool) {
      do {
        if mixWithOthers {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers, .duckOthers]
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []
          )
        }
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        print("Failed to reactivate audio session: \(error)")
      }
    }
  }
#endif
