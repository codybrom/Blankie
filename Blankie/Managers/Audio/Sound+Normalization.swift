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
    guard let player else {
      return
    }

    // Global volume and mix-with-others ride the engine's main mixer; this is
    // only the per-sound contribution.
    let scaledVol = scaledVolume(volume)

    let normalizationSettings = getNormalizationSettings()
    let factor =
      normalizationSettings.normalizeAudio
      ? getNormalizationFactor() : normalizationSettings.volumeAdjustment

    // Node volume caps at 1.0, so boost (factor > 1) goes to the EQ stage in dB and
    // attenuation rides the node volume. The mix-bus limiter catches residual clipping.
    var boostDB: Float = factor > 1 ? 20 * log10(factor) : 0
    if player.isMonoSource && !player.isSpatial {
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
    let customization = SoundCustomizationManager.shared.getCustomization(for: fileName)
    return (
      normalizeAudio: customization?.normalizeAudio ?? true,
      volumeAdjustment: customization?.volumeAdjustment ?? 1.0
    )
  }

  /// Current normalization boost in dB (0 when attenuating). Spatial players
  /// bake this into their mono fold since the EQ isn't in the spatial chain.
  func normalizationBoostDB() -> Float {
    let settings = getNormalizationSettings()
    let factor = settings.normalizeAudio ? getNormalizationFactor() : settings.volumeAdjustment
    return factor > 1 ? 20 * log10(factor) : 0
  }

  private func getNormalizationFactor() -> Float {
    if let normFactor = normalizationFactor {
      return normFactor
    }

    if let lufs = lufs {
      return AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: lufs)
    }

    // No LUFS yet: analyze in the background and use 1.0 meanwhile.
    if lufs == nil {
      Task {
        await analyzeAndUpdateLUFS()
      }
    }

    return 1.0
  }

  /// Runs deferred LUFS analysis if it's missing (called when the sound editor opens).
  @MainActor
  func ensureLUFSAnalysis() {
    Task {
      await analyzeAndUpdateLUFS()
    }
  }

  /// Forces a fresh loudness analysis, overwriting the stored profile and cached
  /// values. The deferred path only fills in missing data.
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
    // A new boost means a different spatial-cache key; re-check on next read.
    spatialReadyCache = nil
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
        ErrorReporter.shared.report(error)
      }
    }

    lufs = profile.integratedLUFS
    normalizationFactor = freshFactor
    updateVolume()
    Logger.sounds.debug(
      "Sound: Re-analysis complete for '\(self.fileName)' - LUFS: \(profile.integratedLUFS), gain: \(profile.gainDB) dB"
    )
  }

  /// Analyzes a custom sound that has no LUFS data and saves the result.
  private func analyzeAndUpdateLUFS() async {
    guard isCustom,
      let customSoundDataID = customSoundDataID
    else {
      Logger.sounds.debug(
        "Sound: Skipping LUFS analysis for '\(self.fileName)' - not a custom sound")
      return
    }

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
      let detectedLUFS = lufsResult.lufs
      let normalizationFactor = lufsResult.normalizationFactor
      let soundFileName = fileName

      await MainActor.run {
        guard let customSoundDataID = self.customSoundDataID,
          let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
        else {
          Logger.sounds.error(
            "Sound: Could not refetch custom sound data for '\(soundFileName, privacy: .public)'")
          return
        }

        customSoundData.detectedLUFS = detectedLUFS
        customSoundData.normalizationFactor = normalizationFactor

        do {
          try CustomSoundManager.shared.saveContext()
          Logger.sounds.debug(
            "Sound: Updated LUFS data for '\(soundFileName)' - LUFS: \(detectedLUFS), Factor: \(normalizationFactor)"
          )

          // Refresh the cached values so getNormalizationFactor() sees the new factor.
          self.lufs = detectedLUFS
          self.normalizationFactor = normalizationFactor

          self.updateVolume()
        } catch {
          Logger.sounds.error(
            "Sound: Failed to save LUFS data for '\(soundFileName, privacy: .public)': \(error, privacy: .public)"
          )
          ErrorReporter.shared.report(error)
        }
      }
    } else {
      Logger.sounds.error("Sound: Failed to analyze LUFS for '\(self.fileName, privacy: .public)'")
    }
  }
}
