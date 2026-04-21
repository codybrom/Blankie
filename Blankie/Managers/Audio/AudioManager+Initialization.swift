//
//  AudioManager+Initialization.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import Combine
import Foundation
import SwiftUI

extension AudioManager {
  func setupSoundObservers() {
    // Clear any existing observers
    cancellables.removeAll()
    // Set up new observers for each sound
    for sound in sounds {
      sound.objectWillChange
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          guard let self = self else { return }
          Task { @MainActor in
            self.updateHasSelectedSounds()
            PresetManager.shared.updateCurrentPresetState()
          }
        }
        .store(in: &cancellables)
    }

    // Update initial state
    updateHasSelectedSounds()
  }

  func updateHasSelectedSounds() {
    let newValue = sounds.contains { $0.isSelected }
    if hasSelectedSounds != newValue {
      print("🎵 AudioManager: hasSelectedSounds changed from \(hasSelectedSounds) to \(newValue)")
      hasSelectedSounds = newValue

      // Auto-start playback when sounds are selected and nothing is currently playing
      // Only auto-start if autoplay is enabled and we're not during initialization
      if newValue && !isGloballyPlaying && !sounds.isEmpty && GlobalSettings.shared.autoPlayOnLaunch
      {
        print("🎵 AudioManager: Auto-starting playback for selected sounds (autoplay enabled)")
        Task { @MainActor in
          setGlobalPlaybackState(true)
        }
      } else if newValue && !isGloballyPlaying && !sounds.isEmpty {
        print("🎵 AudioManager: Selected sounds detected but autoplay disabled - waiting for user")
      }
    }
  }

  #if os(iOS) || os(visionOS)
    func setupAudioSessionForPlayback() {
      AudioSessionManager.shared.setupForPlayback(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isCarPlayConnected: isCarPlayConnected
      )
    }
  #endif
}
