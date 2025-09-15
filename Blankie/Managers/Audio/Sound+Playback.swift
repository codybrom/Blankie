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

  private var loadedPlayer: AVAudioPlayer? {
    // Prevent race conditions by not auto-loading here
    // loadSound() should be called explicitly when needed
    return player
  }

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
      print("❌ Sound: Failed to play '\(fileName)'")
      let error = NSError(
        domain: "SoundPlayback", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to play sound"])
      ErrorReporter.shared.report(AudioError.playbackFailed(error))
    } else {
      print("🔊 Sound: Playing '\(fileName)' from position: \(validPlayer.currentTime)s")
    }
  }

  private func preparePlayer() -> AVAudioPlayer? {
    guard let player = self.player else {
      print("❌ Sound: No player available for '\(fileName)'")
      return nil
    }

    // Additional validation
    if !player.prepareToPlay() {
      print("❌ Sound: Player not ready for '\(fileName)' - attempting to reload")
      loadSound()
      guard let reloadedPlayer = self.player else {
        print("❌ Sound: Failed to reload player for '\(fileName)'")
        return nil
      }
      if !reloadedPlayer.prepareToPlay() {
        print("❌ Sound: Player still not ready after reload for '\(fileName)'")
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
        print(
          "🎲 Sound: Reset '\(fileName)' to random position: \(randomPosition)s of \(player.duration)s (max 75%)"
        )
      } else {
        print(
          "⚠️ Sound: Cannot randomize start position for '\(fileName)' - invalid duration: \(player.duration)"
        )
      }
    } else {
      // Reset to beginning if randomization is disabled
      player.currentTime = 0
      print("🎵 Sound: Reset '\(fileName)' to beginning")
    }
  }

  func pause(immediate: Bool = false) {
    guard let currentPlayer = player else {
      print("🔊 Sound: No player to pause for '\(fileName)'")
      return
    }

    if immediate {
      currentPlayer.stop()
      currentPlayer.currentTime = 0  // Reset to beginning for next play
      print("🔊 Sound: Immediately stopped '\(fileName)'")
    } else {
      currentPlayer.pause()
      print("🔊 Sound: Paused '\(fileName)'")
    }
  }

  func stop() {
    guard let currentPlayer = player else {
      print("🔊 Sound: No player to stop for '\(fileName)'")
      return
    }

    currentPlayer.stop()
    currentPlayer.currentTime = 0  // Reset to beginning for next play
    print("🔊 Sound: Stopped '\(fileName)'")
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

    print("🔊 Sound: Fading in '\(fileName)' over \(duration)s")

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

    print("🔊 Sound: Fading out '\(fileName)' over \(duration)s")

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

    print("🔄 Sound: Resetting '\(fileName)'")

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

    print("✅ Sound: Reset complete for '\(fileName)'")
    isResetting = false
  }

  func updateProgress() {
    guard let player = player, player.duration > 0 else {
      playbackProgress = 0.0
      return
    }

    let newProgress = player.currentTime / player.duration

    // Update on main thread to ensure UI updates
    DispatchQueue.main.async { [weak self] in
      self?.playbackProgress = newProgress

      // Update Now Playing progress if this is the solo mode sound
      if let self = self, AudioManager.shared.soloModeSound?.id == self.id {
        AudioManager.shared.nowPlayingManager.updateProgress(
          currentTime: player.currentTime,
          duration: player.duration
        )
      } else if let self = self {
        // For presets, check if this is the longest playing sound
        let playingSounds = AudioManager.shared.sounds.filter { $0.player?.isPlaying == true }
        let longestSound = playingSounds.max {
          ($0.player?.duration ?? 0) < ($1.player?.duration ?? 0)
        }

        if longestSound?.id == self.id {
          // This is the longest sound, update Now Playing progress
          AudioManager.shared.nowPlayingManager.updateProgress(
            currentTime: player.currentTime,
            duration: player.duration
          )
        }
      }
    }

  }
}
