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
    guard let player else {
      return
    }

    // Global volume and mix-with-others ride the engine's main mixer
    // (AudioEngineManager); this computes only the per-sound contribution.
    let scaledVol = scaledVolume(volume)

    // Apply normalization or manual volume adjustment
    let normalizationSettings = getNormalizationSettings()
    let factor =
      normalizationSettings.normalizeAudio
      ? getNormalizationFactor() : normalizationSettings.volumeAdjustment

    // Split the factor on 1.0: boost (≥1) lands in the EQ stage in dB (node
    // volume is capped at 1.0 and silently eats boosts — the original bug);
    // attenuation (≤1) rides the node volume with the slider. The mix-bus
    // peak limiter guards any residual clipping from boosted sounds.
    var boostDB: Float = factor > 1 ? 20 * log10(factor) : 0
    if player.isMonoSource {
      boostDB += 3.0  // the mixer pans mono inputs ≈3 dB down; compensate
    }
    player.setBoostDB(min(boostDB, 24))

    let effectiveVolume = scaledVol * min(factor, 1)
    if player.volume != effectiveVolume {
      player.volume = effectiveVolume
      Logger.sounds.debug(
        "Sound: Set volume for '\(self.fileName)' to \(effectiveVolume) (boost: \(boostDB) dB)")
    }
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

  /// Forces a fresh loudness analysis, overwriting the stored profile and
  /// cached values. The deferred path only fills *missing* data, so stale
  /// profiles (e.g. pre-cap gains) never refresh without this.
  @MainActor
  func reanalyzeAudio() async {
    guard let url = getSoundURL() else {
      Logger.sounds.error("Sound: Cannot re-analyze '\(self.fileName, privacy: .public)' - no file")
      return
    }
    Logger.sounds.debug("Sound: Re-analyzing audio for '\(self.fileName)'")

    let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: url)
    // Match the keys the loaders read: customs are keyed by bare fileName,
    // built-ins by fileName.extension.
    let profileKey = isCustom ? fileName : "\(fileName).\(fileExtension)"
    guard let profile = PlaybackProfile.from(analysis: analysis, filename: profileKey) else {
      Logger.sounds.error(
        "Sound: Re-analysis produced no profile for '\(self.fileName, privacy: .public)'")
      return
    }

    PlaybackProfileStore.shared.store(profile)
    let freshFactor = pow(10, profile.gainDB / 20)

    if isCustom, let customSoundData {
      customSoundData.detectedLUFS = profile.integratedLUFS
      customSoundData.normalizationFactor = freshFactor
      do {
        try CustomSoundManager.shared.saveContext()
      } catch {
        Logger.sounds.error(
          "Sound: Failed to save re-analysis for '\(self.fileName, privacy: .public)': \(error, privacy: .public)"
        )
      }
    }

    lufs = profile.integratedLUFS
    normalizationFactor = freshFactor
    updateVolume()
    Logger.sounds.debug(
      "Sound: Re-analysis complete for '\(self.fileName)' - LUFS: \(profile.integratedLUFS), gain: \(profile.gainDB) dB"
    )
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
