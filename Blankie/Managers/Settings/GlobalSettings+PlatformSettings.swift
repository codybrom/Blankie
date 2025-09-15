//
//  GlobalSettings+PlatformSettings.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import Foundation

extension GlobalSettings {
  @MainActor
  func setEnableSpatialAudio(_ value: Bool) {
    enableSpatialAudio = value
    UserDefaults.shared.set(value, forKey: UserDefaultsKeys.enableSpatialAudio)
    // Here we would also update the audio engine to enable/disable spatial audio
    logCurrentSettings()
  }

  #if os(iOS) || os(visionOS)
    @MainActor
    func setMixWithOthers(_ value: Bool) {
      mixWithOthers = value
      UserDefaults.shared.set(value, forKey: UserDefaultsKeys.mixWithOthers)

      // Reset volume to 100% when disabling mix with others
      if !value && volumeWithOtherAudio < 1.0 {
        volumeWithOtherAudio = 1.0
        UserDefaults.shared.set(
          volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
      }

      // Update audio session configuration
      updateAudioSession()

      // Apply the new volume settings to currently playing sounds
      if AudioManager.shared.isGloballyPlaying {
        AudioManager.shared.applyVolumeSettings()
      }

      logCurrentSettings()
    }
  #endif

  @MainActor
  func setVolumeWithOtherAudio(_ level: Double) {
    volumeWithOtherAudio = max(0.0, min(1.0, level))  // Clamp between 0.0 and 1.0
    UserDefaults.shared.set(volumeWithOtherAudio, forKey: UserDefaultsKeys.volumeWithOtherAudio)
    // Apply the new volume level to currently playing sounds
    if AudioManager.shared.isGloballyPlaying {
      AudioManager.shared.applyVolumeSettings()
    }
    logCurrentSettings()
  }
}
