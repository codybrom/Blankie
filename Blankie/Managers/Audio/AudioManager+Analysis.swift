//
//  AudioManager+Analysis.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

extension AudioManager {

  /// Analyze all sounds and update their playback profiles
  /// - Parameter forceReanalysis: If true, re-analyze even if profiles exist
  /// - Returns: Number of sounds analyzed
  @MainActor
  func analyzeAllSounds(forceReanalysis: Bool = false) async -> Int {
    debugLog("🔍 AudioManager: Starting batch analysis of all sounds")

    var analyzedCount = 0
    let allSounds = sounds

    // Analyze in batches to avoid overwhelming the system
    let batchSize = 5
    for index in stride(from: 0, to: allSounds.count, by: batchSize) {
      let batch = Array(allSounds[index..<min(index + batchSize, allSounds.count)])

      await withTaskGroup(of: Void.self) { group in
        for sound in batch {
          group.addTask {
            // Check if we need to analyze this sound
            let profileKey = "\(sound.fileName).\(sound.fileExtension)"
            let existingProfile = PlaybackProfileStore.shared.profile(for: profileKey)

            if forceReanalysis || existingProfile == nil {
              // Get the sound URL
              let url: URL?
              if sound.isCustom, let customURL = sound.fileURL {
                url = customURL
              } else {
                url = Bundle.main.url(
                  forResource: sound.fileName, withExtension: sound.fileExtension)
              }

              guard let soundURL = url else {
                debugLog("❌ AudioManager: Could not find URL for \(sound.fileName)")
                return
              }

              // Perform comprehensive analysis
              let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: soundURL)

              // Create and store playback profile
              if let profile = PlaybackProfile.from(analysis: analysis, filename: profileKey) {
                PlaybackProfileStore.shared.store(profile)
                debugLog("✅ AudioManager: Analyzed and stored profile for \(sound.fileName)")

                // Update sound properties
                await MainActor.run {
                  // Note: Sound properties are immutable, so we'd need to reload sounds
                  // or make them mutable to update LUFS values dynamically
                }
              }
            }
          }
        }
      }

      analyzedCount += batch.count
    }

    debugLog("✅ AudioManager: Batch analysis complete. Analyzed \(analyzedCount) sounds")
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
      debugLog(
        "🔍 AudioManager: Found \(customSoundsNeedingAnalysis.count) custom sounds needing analysis")

      for sound in customSoundsNeedingAnalysis {
        guard let url = sound.fileURL else { continue }

        let analysis = await AudioAnalyzer.comprehensiveAnalysis(at: url)
        if let profile = PlaybackProfile.from(analysis: analysis, filename: sound.fileName) {
          PlaybackProfileStore.shared.store(profile)
          debugLog("✅ AudioManager: Analyzed custom sound: \(sound.fileName)")
        }
      }
    }
  }
}
