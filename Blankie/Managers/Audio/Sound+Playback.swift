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

    guard let validPlayer = preparePlayer() else { return }

    // Ensure volume is set before playing
    updateVolume()

    let success = validPlayer.play()
    if !success {
      Logger.sounds.error("Sound: Failed to play '\(self.fileName, privacy: .public)'")
      let error = NSError(
        domain: "SoundPlayback", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to play sound"])
      ErrorReporter.shared.report(AudioError.playbackFailed(error))
    } else {
      Logger.sounds.debug(
        "Sound: Playing '\(self.fileName)' from position: \(validPlayer.currentTime)s")
    }
  }

  private func preparePlayer() -> AVAudioPlayer? {
    guard let player = self.player else {
      Logger.sounds.debug("Sound: No player available for '\(self.fileName)'")
      return nil
    }

    // Additional validation
    if !player.prepareToPlay() {
      Logger.sounds.debug("Sound: Player not ready for '\(self.fileName)' - attempting to reload")
      loadSound()
      guard let reloadedPlayer = self.player else {
        Logger.sounds.error(
          "Sound: Failed to reload player for '\(self.fileName, privacy: .public)'")
        return nil
      }
      if !reloadedPlayer.prepareToPlay() {
        Logger.sounds.debug("Sound: Player still not ready after reload for '\(self.fileName)'")
        return nil
      }
      return reloadedPlayer
    }

    return player
  }

  func resetSoundPosition() {
    guard let player = self.player else {
      // If player doesn't exist yet, it will be randomized when loaded
      return
    }

    // Check if randomize start position is enabled
    // Default to true for both custom and built-in sounds unless explicitly disabled
    let shouldRandomizeStart: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldRandomizeStart = customization.randomizeStartPosition ?? true
    } else {
      shouldRandomizeStart = true  // Default to true for all sounds
    }

    if shouldRandomizeStart {
      // Set a random start position within the sound's duration
      // Check if duration is valid (greater than 0 and not infinite/NaN)
      if player.duration > 0 && player.duration.isFinite {
        // Limit random position to maximum 75% of the duration
        let maxPosition = player.duration * 0.75
        let randomPosition = Double.random(in: 0..<maxPosition)
        player.currentTime = randomPosition
        Logger.sounds.debug(
          "Sound: Reset '\(self.fileName)' to random position: \(randomPosition)s of \(player.duration)s (max 75%)"
        )
      } else {
        Logger.sounds.error(
          "Sound: Cannot randomize start position for '\(self.fileName, privacy: .public)' - invalid duration: \(player.duration, privacy: .public)"
        )
      }
    } else {
      // Reset to beginning if randomization is disabled
      player.currentTime = 0
      Logger.sounds.debug("Sound: Reset '\(self.fileName)' to beginning")
    }
  }

  func pause(immediate: Bool = false) {
    guard let currentPlayer = player else {
      Logger.sounds.debug("Sound: No player to pause for '\(self.fileName)'")
      return
    }

    if immediate {
      currentPlayer.stop()
      currentPlayer.currentTime = 0  // Reset to beginning for next play
      Logger.sounds.debug("Sound: Immediately stopped '\(self.fileName)'")
    } else {
      currentPlayer.pause()
      Logger.sounds.debug("Sound: Paused '\(self.fileName)'")
    }
  }

  func stop() {
    guard let currentPlayer = player else {
      Logger.sounds.debug("Sound: No player to stop for '\(self.fileName)'")
      return
    }

    currentPlayer.stop()
    currentPlayer.currentTime = 0  // Reset to beginning for next play
    Logger.sounds.debug("Sound: Stopped '\(self.fileName)'")
  }

  func fadeIn(duration: TimeInterval = 0.5, completion: (() -> Void)? = nil) {
    // Ensure player is loaded first
    if player == nil {
      loadSound()
    }

    guard let player = self.player else {
      completion?()
      return
    }

    Logger.sounds.debug("Sound: Fading in '\(self.fileName)' over \(duration)s")

    // Store original volume level
    let originalVolume = player.volume
    player.volume = 0.0

    // Start playing if not already
    if !player.isPlaying {
      player.play()
    }

    // Fade in
    fadeTimer?.invalidate()
    fadeStartVolume = 0.0
    targetVolume = originalVolume

    let steps = Int(duration * 30)
    let volumeIncrement = targetVolume / Float(steps)
    let stepDuration = duration / Double(steps)

    var currentStep = 0
    let timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) {
      [weak self] timer in
      guard let self = self else {
        timer.invalidate()
        return
      }

      currentStep += 1
      let newVolume = min(
        self.fadeStartVolume + (volumeIncrement * Float(currentStep)), self.targetVolume)
      self.player?.volume = newVolume

      if currentStep >= steps || newVolume >= self.targetVolume {
        timer.invalidate()
        self.player?.volume = self.targetVolume
        completion?()
      }
    }

    timer.tolerance = stepDuration * 0.1  // Allow 10% variance
    fadeTimer = timer
  }

  func fadeOut(duration: TimeInterval = 0.5, completion: (() -> Void)? = nil) {
    guard let player = self.player, player.isPlaying else {
      completion?()
      return
    }

    Logger.sounds.debug("Sound: Fading out '\(self.fileName)' over \(duration)s")

    fadeTimer?.invalidate()
    fadeStartVolume = player.volume
    targetVolume = 0.0

    let steps = Int(duration * 30)  // 30 steps per second
    let volumeDecrement = fadeStartVolume / Float(steps)
    let stepDuration = duration / Double(steps)

    var currentStep = 0
    let timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) {
      [weak self] timer in
      guard let self = self else {
        timer.invalidate()
        return
      }

      currentStep += 1
      let newVolume = max(self.fadeStartVolume - (volumeDecrement * Float(currentStep)), 0.0)
      self.player?.volume = newVolume

      if currentStep >= steps || newVolume <= 0.0 {
        timer.invalidate()
        self.player?.volume = 0.0
        self.player?.pause()
        completion?()
      }
    }

    timer.tolerance = stepDuration * 0.1  // Allow 10% variance
    fadeTimer = timer
  }

  func reset() {
    guard !isResetting else { return }
    isResetting = true

    Logger.sounds.debug("Sound: Resetting '\(self.fileName)'")

    // Clean up timers
    fadeTimer?.invalidate()
    fadeTimer = nil
    volumeDebounceTimer?.invalidate()
    volumeDebounceTimer = nil
    updateVolumeLogTimer?.invalidate()
    updateVolumeLogTimer = nil

    // Reset player
    player?.stop()
    player = nil

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
