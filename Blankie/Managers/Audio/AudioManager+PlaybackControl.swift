//
//  AudioManager+PlaybackControl.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import AVFoundation
import Foundation
import SwiftUI
import os

extension AudioManager {
  /// Toggles the playback state of all selected sounds; `pauseFadeDuration`
  /// overrides the fade-out ramp when the toggle pauses.
  @MainActor func togglePlayback(pauseFadeDuration: TimeInterval? = nil) {
    setGlobalPlaybackState(!isGloballyPlaying, pauseFadeDuration: pauseFadeDuration)
  }

  @MainActor
  func resetSounds() {
    Logger.audio.debug("AudioManager: Resetting all sounds")

    // First pause all sounds immediately
    for sound in sounds {
      Logger.audio.debug("  - Stopping '\(sound.fileName)'")
      sound.pause(immediate: true)
    }
    setGlobalPlaybackState(false)
    // Reset all sounds
    for sound in sounds {
      sound.volume = 0.75
      sound.isSelected = false
    }
    // Reset "All Sounds" volume
    GlobalSettings.shared.setVolume(1.0)

    // Update hasSelectedSounds after resetting
    updateHasSelectedSounds()

    // Call the reset callback
    onReset?()
    Logger.audio.debug("AudioManager: Reset complete")
  }

  public func updateNowPlayingInfoForPreset(
    preset: Preset? = nil,
    presetName: String? = nil,
    creatorName: String? = nil,
    artworkId: UUID? = nil
  ) {
    Task { @MainActor in
      nowPlayingManager.updateInfo(
        preset: preset,
        presetName: presetName,
        creatorName: creatorName,
        artworkId: artworkId,
        isPlaying: isGloballyPlaying
      )
    }
  }

  func updateNowPlayingState() {
    Task { @MainActor in
      nowPlayingManager.updatePlaybackState(isPlaying: isGloballyPlaying)
    }
  }

  /// Async shim retained for the macOS screenshot path. Forwards to
  /// `setGlobalPlaybackState` so there is a single playback-state authority with
  /// the no-selected-sounds coercion — never a second, weaker copy.
  func setPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    Task { @MainActor [weak self] in
      self?.setGlobalPlaybackState(playing, forceUpdate: forceUpdate)
    }
  }

  func playSelected() {
    Logger.audio.debug("AudioManager: Playing selected sounds")
    guard isGloballyPlaying else {
      Logger.audio.debug("AudioManager: Not playing sounds because global playback is disabled")
      return
    }

    #if os(iOS) || os(visionOS)
      // Setup audio session when starting playback
      setupAudioSessionForPlayback()
      // Setup audio session observers on first playback
      setupAudioSessionObservers()
    #endif

    // If in solo mode, play only the solo sound
    if let soloSound = soloModeSound {
      Logger.audio.debug("  - In solo mode, playing only '\(soloSound.fileName)'")

      // Play the solo sound at its current volume
      soloSound.play()

      // Update Now Playing info for solo mode
      Task { @MainActor in
        nowPlayingManager.updateInfo(
          presetName: soloSound.title,
          isPlaying: true
        )
      }
      return
    }

    // Normal mode: play all selected sounds according to preset
    for sound in sounds where sound.isSelected {
      // Resume paused sounds in place; reset stopped/new/finished ones
      // (respecting randomization). Explicit state replaces currentTime inference.
      if !sound.isPlaying, sound.playbackState != .paused {
        sound.resetSoundPosition()
      }

      sound.play()
    }

    // Update Now Playing info with full preset details
    Task { @MainActor in
      let currentPreset = PresetManager.shared.currentPreset
      self.nowPlayingManager.updateInfo(
        preset: currentPreset,
        presetName: currentPreset?.name,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId,
        isPlaying: true
      )
    }
  }

  /// `fadeDuration` overrides the fade-out ramp (remote pauses pass zero);
  /// nil uses the standard `Sound.fadeDuration`.
  func pauseAll(fadeDuration: TimeInterval? = nil) {
    Logger.audio.debug("AudioManager: Pausing all selected sounds")

    for sound in sounds where sound.isSelected {
      sound.pause(fadeDuration: fadeDuration)
    }

    // Note: We intentionally do NOT deactivate the audio session here
    // This keeps the Now Playing controls visible on lock screen/control center
    // The session will be deactivated when appropriate (background, termination, etc.)

    scheduleEngineIdlePause(afterFade: fadeDuration ?? Sound.fadeDuration)
  }

  /// After the pause fade-outs land, idles the engine and does the single
  /// paused publish (held until then — see performNowPlayingUpdate). The
  /// session stays active so the system controls remain visible.
  private func scheduleEngineIdlePause(afterFade fadeDuration: TimeInterval) {
    Task { @MainActor [weak self] in
      // Zero-length fades pause their nodes synchronously inside pauseAll,
      // so the engine can idle in this same runloop turn — don't sleep.
      if fadeDuration > 0 {
        try? await Task.sleep(for: .seconds(fadeDuration + 0.1))
      }
      // Retry past straggling fades rather than leave the system UI stuck.
      for _ in 0..<8 {
        guard let self, !self.isGloballyPlaying, self.previewModeSound == nil else { return }
        // Already idle (an earlier pause's task won): that pass published.
        guard AudioEngineManager.shared.engine.isRunning else { return }
        if AudioEngineManager.shared.pauseIfIdle() {
          self.nowPlayingManager.republishCurrentPreset()
          return
        }
        try? await Task.sleep(for: .seconds(0.15))
      }
      // Safety net: a player still claims to be rendering after every retry.
      // Globally paused is the truth — force the pause rather than strand the
      // system UI on "playing" (the original stuck-button bug).
      guard let self, !self.isGloballyPlaying, self.previewModeSound == nil else { return }
      Logger.audio.error("AudioManager: Engine never idled after pause; forcing engine pause")
      AudioEngineManager.shared.pause()
      self.nowPlayingManager.republishCurrentPreset()
    }
  }

  /// `pauseFadeDuration` overrides the fade-out ramp when pausing (remote
  /// commands pass `Sound.remotePauseFadeDuration`); ignored on play.
  @MainActor
  public func setGlobalPlaybackState(
    _ playing: Bool, forceUpdate: Bool = false, pauseFadeDuration: TimeInterval? = nil
  ) {
    guard !isInitializing || forceUpdate else {
      Logger.audio.debug("AudioManager: Ignoring setPlaybackState during initialization")
      return
    }

    Logger.audio.debug(
      "AudioManager: Setting playback state to \(playing) - Current global state: \(self.isGloballyPlaying)"
    )

    // There is nothing to play with no selected sounds (and no solo), so coerce
    // any such request to paused. In-app buttons already gate on this; remote
    // commands (lock screen / Control Center / CarPlay) did not, which let the
    // app advertise rate 1.0 over silence and read as "playing" with no sound.
    let shouldPlay = playing && (soloModeSound != nil || hasSelectedSounds)
    if playing && !shouldPlay {
      Logger.audio.debug("AudioManager: Ignoring play request with no selected sounds")
    }

    // Update state first
    isGloballyPlaying = shouldPlay

    // Then handle playback
    if shouldPlay {
      playSelected()
    } else {
      pauseAll(fadeDuration: pauseFadeDuration)
    }

    // Always update Now Playing info with full preset details
    if let soloSound = soloModeSound {
      // In solo mode, just show the sound title
      nowPlayingManager.updateInfo(
        presetName: soloSound.title,
        isPlaying: isGloballyPlaying
      )
    } else {
      // Normal mode - include full preset details
      let currentPreset = PresetManager.shared.currentPreset
      nowPlayingManager.updateInfo(
        preset: currentPreset,
        presetName: currentPreset?.name,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId,
        isPlaying: isGloballyPlaying
      )
    }
  }

  // MARK: - Music Exclusivity

  /// Enforces the one-music-per-preset rule: when `keep` is selected, every
  /// other selected music sound is deselected (fades out) so the mix holds at
  /// most one music sound at a time (last selected wins). Applies to Quick Mix
  /// too. No-op during preset apply / solo, which manage selection themselves.
  func deselectOtherMusicSounds(except keep: Sound) {
    guard soloModeSound == nil, !isApplyingPresetStates else { return }
    for sound in sounds where sound.id != keep.id && sound.isSelected && sound.isMusic {
      Logger.audio.debug(
        "AudioManager: Music '\(sound.fileName)' yields the slot to '\(keep.fileName)'")
      sound.isSelected = false
    }
  }

  // MARK: - Update Playing Sounds

  func updatePlayingSounds() {
    // Stop any sounds that are playing but shouldn't be. Sounds in a fade-out
    // (.paused mid-ramp) are already winding down — hard-stopping them would
    // kill the crossfade.
    for sound in sounds {
      if !sound.isSelected, sound.isPlaying, sound.playbackState == .playing {
        Logger.audio.debug(
          "AudioManager: Stopping deselected sound '\(sound.fileName)' that was still playing")
        sound.pause(immediate: true)
      }
    }
  }
}
