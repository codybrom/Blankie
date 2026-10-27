//
//  Sound+Playback.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Foundation
import os

// MARK: - Playback Controls
extension Sound {

  /// Clips shorter than ~2s skip the play/pause ramp, which would swallow most of the clip.
  private var isTooShortToFade: Bool {
    guard let player else { return false }
    return player.duration < Sound.fadeDuration * 4
  }

  /// Whether play/pause should ramp: per-sound preference (default on), with
  /// the too-short cutoff as a hard floor.
  private var shouldFade: Bool {
    let wantsFade =
      SoundCustomizationManager.shared.getCustomization(for: fileName)?.fadeSound ?? true
    return wantsFade && !isTooShortToFade
  }

  func play() {
    if player == nil {
      loadSound()
    }

    guard let player = self.player else {
      Logger.sounds.debug("Sound: No player available for '\(self.fileName)'")
      return
    }

    // Rescheduling an audible node would restart the sound. A fade-out pause in
    // flight ramps back up.
    guard !player.isPlaying else {
      if playbackState == .paused {
        Logger.sounds.debug("Sound: Rescuing mid-fade pause for '\(self.fileName)'")
        // The idle-pause safety net can pause the engine under a fading node.
        _ = AudioEngineManager.shared.ensureRunning()
        player.fade(to: 1, duration: Sound.fadeDuration)
        playbackState = .playing
      } else {
        Logger.sounds.debug("Sound: '\(self.fileName)' already playing")
      }
      return
    }

    // Re-attach (idempotent; covers engine recreation) and make sure the engine is
    // running, since AVAudioPlayerNode.play() throws otherwise.
    AudioEngineManager.shared.attach(player)
    guard AudioEngineManager.shared.ensureRunning() else {
      Logger.sounds.error(
        "Sound: Engine unavailable for '\(self.fileName, privacy: .public)' - retry scheduled")
      return
    }

    updateVolume()

    // currentFrame is the paused position or the (possibly random) seek target, so
    // this covers resume and fresh start. Starts silent and fades in if fades are on.
    let fadeIn = shouldFade ? Sound.fadeDuration : 0
    player.setFadeLevel(fadeIn > 0 ? 0 : 1)
    player.play(fromFrame: player.currentFrame)
    player.fade(to: 1, duration: fadeIn)
    playbackState = .playing
    Logger.sounds.debug(
      "Sound: Playing '\(self.fileName)' from position: \(player.currentTime)s")
  }

  /// Repositions a non-playing sound for its next start: a random point in the
  /// first 75% of a looping clip, or the beginning otherwise.
  func resetSoundPosition() {
    guard let player = self.player else {
      return
    }

    guard !player.isPlaying else { return }

    let shouldRandomizeStart: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldRandomizeStart = customization.randomizeStartPosition ?? true
    } else {
      shouldRandomizeStart = true
    }

    // Random starts only make sense for looping beds (the loop wraps); a
    // one-shot started mid-file just loses its beginning.
    if shouldRandomizeStart && player.loops {
      guard player.duration > 0, player.duration.isFinite else {
        Logger.sounds.error(
          "Sound: Cannot randomize start position for '\(self.fileName, privacy: .public)' - invalid duration: \(player.duration, privacy: .public)"
        )
        return
      }
      let maxFrame = AVAudioFramePosition(Double(player.totalFrames) * 0.75)
      let randomFrame = AVAudioFramePosition.random(in: 0..<max(maxFrame, 1))
      player.seek(toFrame: randomFrame)
      Logger.sounds.debug(
        "Sound: Reset '\(self.fileName)' to random position: \(Double(randomFrame) / player.sampleRate)s of \(player.duration)s (max 75%)"
      )
    } else {
      player.seek(toFrame: 0)
      Logger.sounds.debug("Sound: Reset '\(self.fileName)' to beginning")
    }

    // Seeking clears any paused schedule, so the next play() schedules fresh.
    playbackState = .stopped
  }

  /// `fadeDuration` overrides the standard ramp (nil = `Sound.fadeDuration`);
  /// zero still pauses in place, unlike `immediate`, which stops and clears position.
  func pause(immediate: Bool = false, fadeDuration requestedFade: TimeInterval? = nil) {
    guard let currentPlayer = player else { return }

    if immediate {
      currentPlayer.stop()
      playbackState = .stopped
      Logger.sounds.debug("Sound: Immediately stopped '\(self.fileName)'")
    } else {
      // Nothing audible to fade. A .stopped sound must not become .paused (that
      // would break resume).
      guard currentPlayer.isPlaying || playbackState == .playing else { return }
      // State flips to .paused at once so UI and playback logic treat the sound as
      // paused during the ramp; play() can ramp a mid-fade pause back up.
      playbackState = .paused
      currentPlayer.fade(to: 0, duration: shouldFade ? (requestedFade ?? Sound.fadeDuration) : 0) {
        [weak currentPlayer] in
        currentPlayer?.pause()
      }
      Logger.sounds.debug("Sound: Fading out and pausing '\(self.fileName)'")
    }
  }

  func stop() {
    guard let currentPlayer = player else {
      Logger.sounds.debug("Sound: No player to stop for '\(self.fileName)'")
      return
    }

    currentPlayer.stop()
    playbackState = .stopped
    Logger.sounds.debug("Sound: Stopped '\(self.fileName)'")
  }

  /// Rebuilds the player when the loop preference changes (`loops` is fixed at
  /// creation). A playing sound resumes in the new mode.
  func reloadForLoopChange() {
    guard let player else { return }  // not loaded: next load reads the new value

    let desiredLoop =
      SoundCustomizationManager.shared.getCustomization(for: fileName)?.loopSound ?? true
    guard player.loops != desiredLoop else { return }

    let wasPlaying = playbackState == .playing
    Logger.sounds.debug(
      "Sound: Reloading '\(self.fileName)' for loop change (loops=\(desiredLoop), wasPlaying=\(wasPlaying))"
    )
    unload()
    loadSound()
    if wasPlaying {
      play()
    }
  }

  func reset() {
    guard !isResetting else { return }
    isResetting = true

    Logger.sounds.debug("Sound: Resetting '\(self.fileName)'")

    volumeDebounceTimer?.invalidate()
    volumeDebounceTimer = nil

    unload()

    isSelected = false
    volume = 0.75

    UserDefaults.shared.removeObject(forKey: "\(fileName)_isSelected")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_volume")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_isHidden")

    // `volume = 0.75` above re-armed the debounced save; cancel it so it can't
    // rewrite the removed key.
    volumeDebounceTimer?.invalidate()
    volumeDebounceTimer = nil

    Logger.sounds.debug("Sound: Reset complete for '\(self.fileName)'")
    isResetting = false
  }
}
