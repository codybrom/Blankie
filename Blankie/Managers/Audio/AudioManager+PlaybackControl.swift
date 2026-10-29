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
  /// Toggles the playback state of all selected sounds. `pauseFadeDuration`
  /// overrides the fade-out ramp when the toggle pauses.
  @MainActor func togglePlayback(pauseFadeDuration: TimeInterval? = nil) {
    setGlobalPlaybackState(!isGloballyPlaying, pauseFadeDuration: pauseFadeDuration)
  }

  /// Tapping a sound tile or row: while playing, toggles the sound in or out of
  /// the mix, and while paused, selects it and resumes. `updateHasSelectedSounds()`
  /// publishes the selection before the coalesced pass.
  @MainActor func toggleOrResume(_ sound: Sound) {
    if !isGloballyPlaying {
      if !sound.isSelected {
        sound.isSelected = true
        updateHasSelectedSounds()
      }
      setGlobalPlaybackState(true)
    } else {
      sound.toggle()
      if !collapseUnsavedMixIfOneSound() {
        refreshUnsavedMixName()
      }
    }
  }

  @MainActor
  func resetSounds() {
    Logger.audio.debug("AudioManager: Resetting all sounds")

    for sound in sounds {
      Logger.audio.debug("  - Stopping '\(sound.fileName)'")
      sound.pause(immediate: true)
    }
    setGlobalPlaybackState(false)
    for sound in sounds {
      sound.volume = 0.75
      sound.isSelected = false
    }
    // The "All Sounds" volume.
    GlobalSettings.shared.setVolume(1.0)

    updateHasSelectedSounds()

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

  /// Async shim for the macOS screenshot path. Forwards to `setGlobalPlaybackState`.
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
      setupAudioSessionForPlayback()
    #endif

    if let singleSound = singleSound {
      Logger.audio.debug("  - In single-sound mode, playing only '\(singleSound.fileName)'")

      singleSound.play()

      // Read the state when the Task runs so a pause queued ahead of it wins.
      Task { @MainActor in
        nowPlayingManager.updateInfo(
          presetName: singleSound.title,
          isPlaying: self.isGloballyPlaying
        )
      }
      return
    }

    for sound in sounds where sound.isSelected {
      // Paused sounds resume in place, while stopped, new or finished ones reset
      // (respecting randomization).
      if !sound.isPlaying, sound.playbackState != .paused {
        sound.resetSoundPosition()
      }

      sound.play()
    }

    Task { @MainActor in
      let currentPreset = PresetManager.shared.currentPreset
      self.nowPlayingManager.updateInfo(
        preset: currentPreset,
        presetName: currentPreset?.name,
        creatorName: currentPreset?.creatorName,
        artworkId: currentPreset?.artworkId,
        isPlaying: self.isGloballyPlaying
      )
    }
  }

  /// `fadeDuration` overrides the fade-out ramp (remote pauses pass zero), and
  /// nil uses the standard `Sound.fadeDuration`.
  func pauseAll(fadeDuration: TimeInterval? = nil) {
    Logger.audio.debug("AudioManager: Pausing all selected sounds")

    for sound in sounds where sound.isSelected {
      sound.pause(fadeDuration: fadeDuration)
    }

    // The session stays active so Now Playing controls remain on the lock screen
    // and in Control Center.

    scheduleEngineIdlePause(afterFade: fadeDuration ?? Sound.fadeDuration)
  }

  /// After the pause fade-outs land, idles the engine and does the single paused
  /// publish, held until then (see performNowPlayingUpdate).
  func scheduleEngineIdlePause(afterFade fadeDuration: TimeInterval) {
    Task { @MainActor [weak self] in
      // Zero-length fades pause their nodes synchronously in pauseAll, so the
      // engine can idle this runloop turn.
      if fadeDuration > 0 {
        try? await Task.sleep(for: .seconds(fadeDuration + 0.1))
      }
      // Retries cover fades that finish late.
      for _ in 0..<8 {
        guard let self, !self.isGloballyPlaying, self.previewModeSound == nil else { return }
        // Already idle: an earlier pause's task published.
        guard AudioEngineManager.shared.engine.isRunning else { return }
        if AudioEngineManager.shared.pauseIfIdle() {
          self.nowPlayingManager.republishCurrentPreset()
          return
        }
        try? await Task.sleep(for: .seconds(0.15))
      }
      // A player still reports rendering after every retry. Global state says
      // paused, so force the engine pause and keep the system UI accurate.
      guard let self, !self.isGloballyPlaying, self.previewModeSound == nil else { return }
      Logger.audio.error("AudioManager: Engine never idled after pause; forcing engine pause")
      AudioEngineManager.shared.pause()
      self.nowPlayingManager.republishCurrentPreset()
    }
  }

  /// `pauseFadeDuration` overrides the fade-out ramp when pausing (remote
  /// commands pass `Sound.remotePauseFadeDuration`) and is ignored on play.
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

    // With nothing selected (and no single sound), every play request, remote ones
    // included, becomes a pause so Now Playing never reports rate 1.0 over silence.
    let shouldPlay = playing && hasPlayableSelection
    if playing && !shouldPlay {
      Logger.audio.debug("AudioManager: Ignoring play request with no selected sounds")
    }

    isGloballyPlaying = shouldPlay
    #if os(iOS) || os(visionOS)
      // Explicit playback requests supersede automatic interruption recovery,
      // including a pause from Siri, a sleep timer, or a disconnected route.
      wasPlayingWhenInterrupted = false
    #endif
    if shouldPlay {
      // Keeps the macOS open-time autoplay from firing later.
      launchAutoPlayHandled = true
    }

    // Any play or pause ends a sound-editor preview, except a play ignored for
    // an empty mix. Playback below restarts or pauses the mix itself.
    if !playing || shouldPlay {
      exitPreviewMode(resuming: false, pauseFadeDuration: pauseFadeDuration)
    }

    if shouldPlay {
      playSelected()
    } else {
      pauseAll(fadeDuration: pauseFadeDuration)
    }

    // WidgetKit can reload as soon as a widget intent returns, so publish before
    // the Now Playing debounce or the engine's pause fade.
    publishCurrentWidgetSnapshot()

    if let singleSound = singleSound {
      nowPlayingManager.updateInfo(
        presetName: singleSound.title,
        isPlaying: isGloballyPlaying
      )
    } else {
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

  /// Whether there's a single sound or any selected sound. Reads the live selection
  /// because `hasSelectedSounds` lags. Intents and preset apply play right after selecting.
  var hasPlayableSelection: Bool {
    singleSound != nil || sounds.contains { $0.isSelected }
  }

  // MARK: - Music Exclusivity

  /// One music sound per mix (Quick Mix included): selecting `keep` deselects any
  /// other music sound. No-op during preset apply and single sound, which manage selection.
  func deselectOtherMusicSounds(except keep: Sound) {
    guard singleSound == nil, !isApplyingPresetStates else { return }
    for sound in sounds where sound.id != keep.id && sound.isSelected && sound.isMusic {
      Logger.audio.debug(
        "AudioManager: Music '\(sound.fileName)' yields the slot to '\(keep.fileName)'")
      sound.isSelected = false
    }
  }

  // MARK: - Update Playing Sounds

  func updatePlayingSounds() {
    // Stop deselected sounds still playing. Skip ones mid fade-out (.paused), so
    // the crossfade finishes.
    for sound in sounds {
      if !sound.isSelected, sound.isPlaying, sound.playbackState == .playing {
        Logger.audio.debug(
          "AudioManager: Stopping deselected sound '\(sound.fileName)' that was still playing")
        sound.pause(immediate: true)
      }
    }
  }
}
