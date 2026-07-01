//
//  AudioManager+Analysis.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI
import os

extension AudioManager {

  /// Analyze all sounds and update their playback profiles
  /// - Parameter forceReanalysis: If true, re-analyze even if profiles exist
  /// - Returns: Number of sounds analyzed
  @MainActor
  func analyzeAllSounds(forceReanalysis: Bool = false) async -> Int {
    Logger.audio.debug("AudioManager: Starting batch analysis of all sounds")

    var analyzedCount = 0
    let allSounds = sounds

    // Analyze in batches to avoid overwhelming the system
    let batchSize = 5
    for index in stride(from: 0, to: allSounds.count, by: batchSize) {
      let batch = Array(allSounds[index..<min(index + batchSize, allSounds.count)])

      await withTaskGroup(of: Void.self) { group in
        for sound in batch {
          // Read main-actor `Sound` state here (on the main actor) before handing
          // the work to a background task — `Sound` is main-actor and non-Sendable,
          // so only these Sendable values cross into the task.
          // Custom profiles are keyed by the bare fileName; built-ins by
          // fileName.extension (matches soundsNeedingAnalysis and delete-cleanup).
          let isCustom = sound.isCustom
          let fileName = sound.fileName
          let fileExtension = sound.fileExtension
          let customURL = isCustom ? sound.fileURL : nil
          let profileKey = isCustom ? fileName : "\(fileName).\(fileExtension)"

          group.addTask {
            let existingProfile = PlaybackProfileStore.shared.profile(for: profileKey)

            if forceReanalysis || existingProfile == nil {
              // Get the sound URL
              let url: URL?
              if isCustom, let customURL {
                url = customURL
              } else {
                url = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
              }

              guard let soundURL = url else {
                Logger.audio.error(
                  "AudioManager: Could not find URL for \(fileName, privacy: .public)")
                return
              }

              // Perform comprehensive analysis
              let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: soundURL)

              // Create and store playback profile
              if let profile = PlaybackProfile.from(analysis: analysis, filename: profileKey) {
                PlaybackProfileStore.shared.store(profile)
                Logger.audio.debug(
                  "AudioManager: Analyzed and stored profile for \(fileName)")
              }
            }
          }
        }
      }

      analyzedCount += batch.count
    }

    Logger.audio.debug("AudioManager: Batch analysis complete. Analyzed \(analyzedCount) sounds")
    return analyzedCount
  }

  /// Check if any sounds need analysis
  @MainActor
  func soundsNeedingAnalysis() -> [Sound] {
    return sounds.filter { sound in
      let profileKey = sound.isCustom ? sound.fileName : "\(sound.fileName).\(sound.fileExtension)"
      return PlaybackProfileStore.shared.profile(for: profileKey) == nil
    }
  }

  /// Analyze all custom sounds missing profiles (useful for migration)
  @MainActor
  func analyzeCustomSoundsIfNeeded() async {
    let customSoundsNeedingAnalysis = sounds.filter { sound in
      if !sound.isCustom { return false }
      let profileKey = sound.fileName
      return PlaybackProfileStore.shared.profile(for: profileKey) == nil
    }

    if !customSoundsNeedingAnalysis.isEmpty {
      Logger.audio.debug(
        "AudioManager: Found \(customSoundsNeedingAnalysis.count) custom sounds needing analysis")

      for sound in customSoundsNeedingAnalysis {
        guard let url = sound.fileURL else { continue }

        let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: url)
        if let profile = PlaybackProfile.from(analysis: analysis, filename: sound.fileName) {
          PlaybackProfileStore.shared.store(profile)
          Logger.audio.debug("AudioManager: Analyzed custom sound: \(sound.fileName)")
        }
      }
    }
  }
}
