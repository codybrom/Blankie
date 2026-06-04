//
//  GlobalSettings+AudioSession.swift
//  Blankie
//
//  Created by Cody Bromley on 6/2/25.
//

import AVFoundation
import Foundation

#if os(iOS) || os(visionOS)
  extension GlobalSettings {
    func updateAudioSession() {
      do {
        let wasPlaying = AudioManager.shared.isGloballyPlaying

        // Configure the session based on mixWithOthers setting
        if mixWithOthers {
          // Allow mixing with other apps - we handle volume manually
          let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
          debugLog("GlobalSettings: Setting Mix mode with manual volume control")

          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: options
          )
        } else {
          // Exclusive playback mode - no mixing
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // No options means exclusive playback
          )
        }

        // Always activate if we're currently playing to ensure we take over
        if wasPlaying {
          try AVAudioSession.sharedInstance().setActive(true)

          // Note: We don't call playSelected() here to preserve playback positions
          // The audio players will automatically continue from their current positions

          // Update Now Playing info
          AudioManager.shared.updateNowPlayingState()
        }

        debugLog(
          "GlobalSettings: Updated audio session with mixWithOthers: \(mixWithOthers), volumeWithOtherAudio: \(volumeWithOtherAudio), activated: \(wasPlaying)"
        )
      } catch {
        debugLog("GlobalSettings: Failed to update audio session: \(error)")
      }
    }
  }
#endif
