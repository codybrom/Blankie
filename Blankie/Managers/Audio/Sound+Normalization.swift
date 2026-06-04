//
//  Sound+Normalization.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Foundation
import os

// MARK: - Normalization & LUFS Analysis
extension Sound {

  func updateVolume() {
    // Skip volume calculations during app initialization when no player exists
    guard player != nil else {
      return
    }
    let scaledVol = scaledVolume(volume)
    var effectiveVolume = scaledVol * Float(GlobalSettings.shared.volume)

    // Apply custom volume level when mixing with other audio
    if GlobalSettings.shared.mixWithOthers {
      effectiveVolume *= Float(GlobalSettings.shared.volumeWithOtherAudio)
    }

    // Apply normalization and volume adjustment
    let normalizationSettings = getNormalizationSettings()
    if normalizationSettings.normalizeAudio {
      // Use detected peak level if available, otherwise use default
      let normalizationFactor = getNormalizationFactor()
      effectiveVolume *= normalizationFactor
      // When normalization is enabled, ignore volume adjustment
    } else {
      // Only apply volume adjustment when normalization is disabled
      effectiveVolume *= normalizationSettings.volumeAdjustment
    }

    // Apply soft limiting if needed to prevent clipping
    if needsLimiter && effectiveVolume > 0.95 {
      // Simple soft clipping function using tanh
      // This provides a smooth transition as we approach 1.0
      let softLimitThreshold: Float = 0.85
      if effectiveVolume > softLimitThreshold {
        let excess = (effectiveVolume - softLimitThreshold) / (1.0 - softLimitThreshold)
        let limited = softLimitThreshold + (1.0 - softLimitThreshold) * tanh(excess * 2)
        Logger.sounds.debug(
          "Sound: Applying soft limiter to '\(self.fileName)' - from \(effectiveVolume) to \(limited)"
        )
        effectiveVolume = limited
      }
    }

    // Only log volume calculations if they actually change the player volume
    if player?.volume != effectiveVolume {
      player?.volume = effectiveVolume
      Logger.sounds.debug("Sound: Set player volume for '\(self.fileName)' to \(effectiveVolume)")

      // Debounce just the print statement
      updateVolumeLogTimer?.invalidate()
      updateVolumeLogTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
        [weak self] _ in
        guard let self = self else { return }
        Logger.sounds.debug("Sound: Updated '\(self.fileName)' volume to \(effectiveVolume)")
      }
    }
    // Remove "Volume already at" logging - too verbose for production
  }

  private func scaledVolume(_ linear: Float) -> Float {
    return pow(linear, 3)
  }

  private func getNormalizationSettings() -> (normalizeAudio: Bool, volumeAdjustment: Float) {
    // Now using unified customization for all sounds
    let customization = SoundCustomizationManager.shared.getCustomization(for: fileName)
    return (
      normalizeAudio: customization?.normalizeAudio ?? true,
      volumeAdjustment: customization?.volumeAdjustment ?? 1.0
    )
  }

  private func getNormalizationFactor() -> Float {
    // Use pre-computed normalization factor from Sound initialization
    if let normFactor = normalizationFactor {
      return normFactor
    }

    // Fall back to LUFS calculation if available
    if let lufs = lufs {
      return AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: lufs)
    }

    // If no LUFS data available, trigger async analysis
    if lufs == nil {
      Task {
        await analyzeAndUpdateLUFS()
      }
    }

    // Default normalization factor for sounds without analysis
    return 1.0
  }

  /// Public method to trigger LUFS analysis when sound editor is opened
  @MainActor
  func ensureLUFSAnalysis() {
    Task {
      await analyzeAndUpdateLUFS()
    }
  }

  /// Analyze LUFS for this sound if missing and update the data
  private func analyzeAndUpdateLUFS() async {
    // Only analyze custom sounds that are missing LUFS data
    guard isCustom,
      let customSoundDataID = customSoundDataID
    else {
      Logger.sounds.debug(
        "Sound: Skipping LUFS analysis for '\(self.fileName)' - not a custom sound")
      return
    }

    // Get file URL and check if analysis is needed on MainActor
    let fileURL = await MainActor.run { () -> URL? in
      guard let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID),
        customSoundData.detectedLUFS == nil,
        let fileURL = CustomSoundManager.shared.getURLForCustomSound(customSoundData)
      else {
        return nil
      }
      return fileURL
    }

    guard let analysisURL = fileURL else {
      Logger.sounds.debug(
        "Sound: Skipping LUFS analysis for '\(self.fileName)' - already has LUFS data or file not found"
      )
      return
    }

    Logger.sounds.debug("Sound: Starting LUFS analysis for custom sound '\(self.fileName)'")

    if let lufsResult = await AudioAnalyzer.analyzeLUFS(at: analysisURL) {
      // Capture the values we need before the MainActor run
      let detectedLUFS = lufsResult.lufs
      let normalizationFactor = lufsResult.normalizationFactor
      let soundFileName = fileName

      await MainActor.run {
        // Re-fetch the custom sound data on the main actor to ensure thread safety
        guard let customSoundDataID = self.customSoundDataID,
          let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
        else {
          Logger.sounds.error(
            "Sound: Could not refetch custom sound data for '\(soundFileName, privacy: .public)'")
          return
        }

        // Update the custom sound data
        customSoundData.detectedLUFS = detectedLUFS
        customSoundData.normalizationFactor = normalizationFactor

        // Save to database
        do {
          try CustomSoundManager.shared.saveContext()
          Logger.sounds.debug(
            "Sound: Updated LUFS data for '\(soundFileName)' - LUFS: \(detectedLUFS), Factor: \(normalizationFactor)"
          )

          // Update this Sound's own cached values so `getNormalizationFactor()`
          // returns the fresh factor instead of the stale init-time nil.
          self.lufs = detectedLUFS
          self.normalizationFactor = normalizationFactor

          // Trigger volume update to apply new normalization
          self.updateVolume()
        } catch {
          Logger.sounds.error(
            "Sound: Failed to save LUFS data for '\(soundFileName, privacy: .public)': \(error, privacy: .public)"
          )
        }
      }
    } else {
      Logger.sounds.error("Sound: Failed to analyze LUFS for '\(self.fileName, privacy: .public)'")
    }
  }
}
