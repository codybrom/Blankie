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

  func play() {
    // Ensure player is loaded first
    if player == nil {
      loadSound()
    }

    guard let player = self.player else {
      Logger.sounds.debug("Sound: No player available for '\(self.fileName)'")
      return
    }

    // Already audible — rescheduling would audibly restart the sound. If a
    // fade-out pause is in flight, rescue it by ramping back up instead.
    guard !player.isPlaying else {
      if playbackState == .paused {
        Logger.sounds.debug("Sound: Rescuing mid-fade pause for '\(self.fileName)'")
        player.fade(to: 1, duration: Sound.fadeDuration)
        playbackState = .playing
      } else {
        Logger.sounds.debug("Sound: '\(self.fileName)' already playing")
      }
      return
    }

    // Re-attach (idempotent; covers engine recreation) and make sure the
    // engine is live — AVAudioPlayerNode.play() throws if it isn't.
    AudioEngineManager.shared.attach(player)
    guard AudioEngineManager.shared.ensureRunning() else {
      Logger.sounds.error(
        "Sound: Engine unavailable for '\(self.fileName, privacy: .public)' - retry scheduled")
      return
    }

    // Ensure volume is set before playing
    updateVolume()

    // One path for resume and fresh start: currentFrame is the paused position
    // for .paused sounds, the (possibly randomized) seek target otherwise.
    // Start silent, then fade in.
    player.setFadeLevel(0)
    player.play(fromFrame: player.currentFrame)
    player.fade(to: 1, duration: Sound.fadeDuration)
    playbackState = .playing
    Logger.sounds.debug(
      "Sound: Playing '\(self.fileName)' from position: \(player.currentTime)s")
  }

  /// Repositions a non-playing sound for its next start: a random point in the
  /// first 75% of the clip, or the beginning when randomization is off.
  func resetSoundPosition() {
    guard let player = self.player else {
      // If player doesn't exist yet, it will be positioned when loaded
      return
    }

    // Never reposition live playback (matches the old currentTime semantics:
    // callers only reset stopped/paused sounds).
    guard !player.isPlaying else { return }

    // Check if randomize start position is enabled
    // Default to true for both custom and built-in sounds unless explicitly disabled
    let shouldRandomizeStart: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldRandomizeStart = customization.randomizeStartPosition ?? true
    } else {
      shouldRandomizeStart = true  // Default to true for all sounds
    }

    if shouldRandomizeStart {
      guard player.duration > 0, player.duration.isFinite else {
        Logger.sounds.error(
          "Sound: Cannot randomize start position for '\(self.fileName, privacy: .public)' - invalid duration: \(player.duration, privacy: .public)"
        )
        return
      }
      // Limit random position to maximum 75% of the duration
      let maxFrame = AVAudioFramePosition(Double(player.totalFrames) * 0.75)
      let randomFrame = AVAudioFramePosition.random(in: 0..<max(maxFrame, 1))
      player.seek(toFrame: randomFrame)
      Logger.sounds.debug(
        "Sound: Reset '\(self.fileName)' to random position: \(Double(randomFrame) / player.sampleRate)s of \(player.duration)s (max 75%)"
      )
    } else {
      // Reset to beginning if randomization is disabled
      player.seek(toFrame: 0)
      Logger.sounds.debug("Sound: Reset '\(self.fileName)' to beginning")
    }

    // Seeking clears any paused schedule, so the next play() must schedule
    // fresh rather than resume.
    playbackState = .stopped
  }

  func pause(immediate: Bool = false) {
    guard let currentPlayer = player else { return }

    if immediate {
      currentPlayer.stop()
      playbackState = .stopped
      Logger.sounds.debug("Sound: Immediately stopped '\(self.fileName)'")
    } else {
      // Nothing audible to fade (already stopped/paused) — bail rather than
      // flip a .stopped sound to .paused and corrupt resume semantics.
      guard currentPlayer.isPlaying || playbackState == .playing else { return }
      // Fade out, then pause. State flips to .paused right away so UI and
      // playback logic treat the sound as paused during the ramp; play() can
      // rescue a mid-fade pause by ramping back up.
      playbackState = .paused
      currentPlayer.fade(to: 0, duration: Sound.fadeDuration) { [weak currentPlayer] in
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

  func reset() {
    guard !isResetting else { return }
    isResetting = true

    Logger.sounds.debug("Sound: Resetting '\(self.fileName)'")

    // Clean up timers
    volumeDebounceTimer?.invalidate()
    volumeDebounceTimer = nil

    // Tear down playback (stops, detaches from the engine, releases)
    unload()

    // Reset state
    isSelected = false
    volume = 0.75

    // Clear user defaults
    UserDefaults.shared.removeObject(forKey: "\(fileName)_isSelected")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_volume")
    UserDefaults.shared.removeObject(forKey: "\(fileName)_isHidden")

    Logger.sounds.debug("Sound: Reset complete for '\(self.fileName)'")
    isResetting = false
  }
}
