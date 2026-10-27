//
//  AudioManager+PreviewMode.swift
//  Blankie
//
//  Created by Cody Bromley on 10/27/26.
//

import Foundation
import os

extension AudioManager {
  // MARK: - Preview Mode (for SoundSheet previews)

  @MainActor
  func enterPreviewMode(for sound: Sound) {
    Logger.audio.debug("AudioManager: Entering preview mode for '\(sound.title)'")

    // Persist a pending (coalesced) mix edit before preview stops preset saves.
    PresetManager.shared.updateCurrentPresetState()

    previewModeOriginalStates.removeAll()
    for existingSound in sounds {
      previewModeOriginalStates[existingSound.fileName] = PreviewOriginalState(
        volume: existingSound.volume,
        isPlaying: existingSound.isPlaying
      )
    }

    for otherSound in sounds where otherSound.id != sound.id {
      if otherSound.isPlaying {
        otherSound.pause()
      }
    }

    previewModeSound = sound

    #if os(iOS) || os(visionOS)
      // Previews play while globally paused, when playSelected() (which normally
      // activates the session) never runs.
      setupAudioSessionForPlayback()
    #endif

    sound.volume = 1.0

    if !sound.isLoaded {
      sound.loadSound()
    }

    // Applies any temporary customizations on top of full volume.
    sound.updateVolume()

    let wasAlreadyPlaying = previewModeOriginalStates[sound.fileName]?.isPlaying ?? false
    if !wasAlreadyPlaying {
      sound.resetSoundPosition()
    }
    sound.play()

    Logger.audio.debug("AudioManager: Preview mode started for '\(sound.title)'")
  }

  /// `resuming: false` restores volumes without restarting the pre-preview
  /// mix, for callers that start or replace playback right after.
  @MainActor
  func exitPreviewMode(resuming: Bool = true, pauseFadeDuration: TimeInterval? = nil) {
    guard let previewSound = previewModeSound else { return }
    Logger.audio.debug("AudioManager: Exiting preview mode for '\(previewSound.title)'")

    let previewSoundWasPlaying =
      previewModeOriginalStates[previewSound.fileName]?.isPlaying ?? false
    if !previewSoundWasPlaying {
      previewSound.pause(fadeDuration: pauseFadeDuration)
    }

    for sound in sounds {
      if let originalState = previewModeOriginalStates[sound.fileName] {
        sound.volume = originalState.volume
        sound.updateVolume()

        // isSelected can flip mid-preview, so a deselected sound stays off. No
        // isPlaying guard: play() rescues a sound mid fade-out, since
        // node.isPlaying lags playbackState by about 0.5s.
        if resuming, originalState.isPlaying, isGloballyPlaying, sound.isSelected {
          sound.play()
        }
      }
    }

    previewModeSound = nil
    previewModeOriginalStates.removeAll()

    // A mix emptied during the preview pauses now.
    updateHasSelectedSounds()

    // A preview while paused ran the engine. Idle it after the fade so iOS
    // stops reporting the app as playing.
    if !isGloballyPlaying {
      scheduleEngineIdlePause(afterFade: Sound.fadeDuration)
    }

    Logger.audio.debug("AudioManager: Preview mode exited")
  }
}
