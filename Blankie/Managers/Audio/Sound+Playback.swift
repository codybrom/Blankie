//
//  Sound+Playback.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Foundation

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
      logError("Sound: Failed to play '\(fileName)'", .sounds)
      let error = NSError(
        domain: "SoundPlayback", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to play sound"])
      ErrorReporter.shared.report(AudioError.playbackFailed(error))
    } else {
      debugLog("Sound: Playing '\(fileName)' from position: \(validPlayer.currentTime)s", .sounds)
    }
  }

  private func preparePlayer() -> AVAudioPlayer? {
    guard let player = self.player else {
      debugLog("Sound: No player available for '\(fileName)'", .sounds)
      return nil
    }

    // Additional validation
    if !player.prepareToPlay() {
      debugLog("Sound: Player not ready for '\(fileName)' - attempting to reload", .sounds)
      loadSound()
      guard let reloadedPlayer = self.player else {
        logError("Sound: Failed to reload player for '\(fileName)'", .sounds)
        return nil
      }
      if !reloadedPlayer.prepareToPlay() {
        debugLog("Sound: Player still not ready after reload for '\(fileName)'", .sounds)
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
        debugLog(
          "Sound: Reset '\(fileName)' to random position: \(randomPosition)s of \(player.duration)s (max 75%)", .sounds
        )
      } else {
        logError(
          "Sound: Cannot randomize start position for '\(fileName)' - invalid duration: \(player.duration)", .sounds
        )
      }
    } else {
      // Reset to beginning if randomization is disabled
      player.currentTime = 0
      debugLog("Sound: Reset '\(fileName)' to beginning", .sounds)
    }
  }

  func pause(immediate: Bool = false) {
    guard let currentPlayer = player else {
      debugLog("Sound: No player to pause for '\(fileName)'", .sounds)
      return
    }

    if immediate {
      currentPlayer.stop()
      currentPlayer.currentTime = 0  // Reset to beginning for next play
      debugLog("Sound: Immediately stopped '\(fileName)'", .sounds)
    } else {
      currentPlayer.pause()
      debugLog("Sound: Paused '\(fileName)'", .sounds)
    }
  }

  func stop() {
    guard let currentPlayer = player else {
      debugLog("Sound: No player to stop for '\(fileName)'", .sounds)
      return
    }

    currentPlayer.stop()
    currentPlayer.currentTime = 0  // Reset to beginning for next play
    debugLog("Sound: Stopped '\(fileName)'", .sounds)
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

    debugLog("Sound: Fading in '\(fileName)' over \(duration)s", .sounds)

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

    debugLog("Sound: Fading out '\(fileName)' over \(duration)s", .sounds)

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

    debugLog("Sound: Resetting '\(fileName)'", .sounds)

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

    debugLog("Sound: Reset complete for '\(fileName)'", .sounds)
    isResetting = false
  }
}
