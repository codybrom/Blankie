//
//  Sound+Loading.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import AVFoundation

extension Sound {

  func getSoundURL() -> URL? {
    if isCustom, let customURL = fileURL {
      // Verify the custom sound file actually exists
      if FileManager.default.fileExists(atPath: customURL.path) {
        debugLog("Sound: Loading custom sound from: \(customURL.path)")
        return customURL
      } else {
        debugLog("Sound: Custom sound file not found at path: \(customURL.path)")
        return nil
      }
    } else {
      debugLog("Sound: Loading built-in sound from bundle")
      return Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    }
  }

  func configurePlayer(_ player: AVAudioPlayer) {
    // Check if sound should loop
    let shouldLoop: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldLoop = customization.loopSound ?? true
    } else {
      shouldLoop = true  // Default to true for all sounds
    }

    player.numberOfLoops = shouldLoop ? -1 : 0  // -1 for infinite, 0 for play once
    player.enableRate = false  // Disable rate/pitch adjustment
    player.delegate = self  // Set delegate to detect when sound finishes
  }

  func applyRandomStartPosition(to player: AVAudioPlayer) {
    // Apply random start position if enabled
    let shouldRandomizeStart: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldRandomizeStart = customization.randomizeStartPosition ?? true
    } else {
      shouldRandomizeStart = true  // Default to true for all sounds
    }

    if shouldRandomizeStart && player.duration > 0 && player.duration.isFinite {
      // Limit random position to maximum 75% of the duration
      let maxPosition = player.duration * 0.75
      let randomPosition = Double.random(in: 0..<maxPosition)
      player.currentTime = randomPosition
      debugLog(
        "Sound: Applied random start position: \(randomPosition)s of \(player.duration)s (max 75%)"
      )
    }
  }

  func validatePlayer(_ player: AVAudioPlayer) -> Bool {
    let prepareSuccess = player.prepareToPlay()
    debugLog("Sound: Prepare to play result for '\(fileName)': \(prepareSuccess)")
    debugLog("Sound: Player duration: \(player.duration), format: \(player.format)")

    if !prepareSuccess || player.duration <= 0 || !player.duration.isFinite {
      debugLog(
        "Sound: Invalid player state - prepareSuccess: \(prepareSuccess), duration: \(player.duration)"
      )
      return false
    }
    return true
  }
}
