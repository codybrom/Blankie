//
//  PlaybackProfile.swift
//  Blankie
//
//  Created by Cody Bromley on 6/5/25.
//

import Foundation
import os

/// Stores pre-computed loudness analysis results for efficient playback
nonisolated struct PlaybackProfile: Codable, Equatable, Sendable {
  let id: String  // Unique identifier (filename or hash)
  let filename: String
  let fileHash: String?  // Optional hash to detect file changes
  let integratedLUFS: Float
  let truePeakdBTP: Float
  let gainDB: Float  // Pre-calculated gain to apply
  let needsLimiter: Bool
  let analysisDate: Date
  let analysisVersion: String  // Track which version of analysis was used

  var targetLUFS: Float {
    AudioAnalyzer.targetLUFS
  }

  var targetTruePeak: Float {
    -1.0  // -1 dBTP as per EBU R 128
  }

  init(
    filename: String,
    fileHash: String? = nil,
    integratedLUFS: Float,
    truePeakdBTP: Float,
    gainDB: Float,
    needsLimiter: Bool
  ) {
    self.id = filename  // Can be enhanced with hash later
    self.filename = filename
    self.fileHash = fileHash
    self.integratedLUFS = integratedLUFS
    self.truePeakdBTP = truePeakdBTP
    self.gainDB = gainDB
    self.needsLimiter = needsLimiter
    self.analysisDate = Date()
    self.analysisVersion = "1.0"
  }

  /// Create a playback profile from audio analysis results
  static func from(analysis: AudioAnalysisResult, filename: String, fileHash: String? = nil)
    -> PlaybackProfile?
  {
    guard let lufs = analysis.lufs,
      let truePeak = analysis.truePeakdBTP
    else {
      return nil
    }

    // Match the analyzer: cap the boost at maxGainDB and apply no gain below
    // minimumLUFS. This cached profile overrides the analyzer's factor at load.
    let targetLUFS = AudioAnalyzer.targetLUFS
    let gainDB =
      lufs > AudioAnalyzer.minimumLUFS
      ? min(targetLUFS - lufs, AudioAnalyzer.maxGainDB)
      : 0

    let predictedTruePeak = truePeak + gainDB
    let targetTruePeak: Float = -1.0  // -1 dBTP

    // Over the true-peak limit, keep the full gain and flag the limiter.
    let finalGainDB: Float
    let needsLimiter: Bool

    if predictedTruePeak > targetTruePeak {
      finalGainDB = gainDB
      needsLimiter = true
    } else {
      finalGainDB = gainDB
      needsLimiter = false
    }

    return PlaybackProfile(
      filename: filename,
      fileHash: fileHash,
      integratedLUFS: lufs,
      truePeakdBTP: truePeak,
      gainDB: finalGainDB,
      needsLimiter: needsLimiter
    )
  }
}

// MARK: - Profile Storage

/// Persists playback profiles. A concurrent `queue` (barrier writes) guards all
/// `profiles` access, so `profile(for:)` works synchronously off the main actor.
/// `loadProfiles()` runs in `init`, before `shared` is published.
nonisolated final class PlaybackProfileStore: @unchecked Sendable {
  static let shared = PlaybackProfileStore()

  private let storageURL: URL = {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let blankieDir = appSupport.appendingPathComponent("Blankie", isDirectory: true)

    try? FileManager.default.createDirectory(at: blankieDir, withIntermediateDirectories: true)

    return blankieDir.appendingPathComponent("playbackProfiles.json")
  }()

  private var profiles: [String: PlaybackProfile] = [:]
  private let queue = DispatchQueue(
    label: "com.blankie.playbackProfileStore", attributes: .concurrent)

  private init() {
    loadProfiles()
  }

  // MARK: - Public API

  func profile(for filename: String) -> PlaybackProfile? {
    queue.sync {
      profiles[filename]
    }
  }

  func store(_ profile: PlaybackProfile) {
    queue.async(flags: .barrier) {
      self.profiles[profile.filename] = profile
      self.saveProfiles()
    }
  }

  func store(_ newProfiles: [PlaybackProfile]) {
    queue.async(flags: .barrier) {
      for profile in newProfiles {
        self.profiles[profile.filename] = profile
      }
      self.saveProfiles()
    }
  }

  func removeProfile(for filename: String) {
    queue.async(flags: .barrier) {
      self.profiles.removeValue(forKey: filename)
      self.saveProfiles()
    }
  }

  /// True when there's no profile or the stored file hash differs.
  func needsUpdate(filename: String, fileHash: String?) -> Bool {
    guard let existingProfile = profile(for: filename) else {
      return true  // No profile exists
    }

    if let existingHash = existingProfile.fileHash,
      let newHash = fileHash
    {
      return existingHash != newHash
    }

    // Without both hashes, assume the profile is current.
    return false
  }

  // MARK: - Private Methods

  private func loadProfiles() {
    guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

    do {
      let data = try Data(contentsOf: storageURL)
      let decodedProfiles = try JSONDecoder().decode([PlaybackProfile].self, from: data)

      for profile in decodedProfiles {
        profiles[profile.filename] = profile
      }

      Logger.presets.debug("PlaybackProfileStore: Loaded \(self.profiles.count) profiles")
    } catch {
      Logger.presets.error(
        "PlaybackProfileStore: Failed to load profiles: \(error, privacy: .public)")
    }
  }

  private func saveProfiles() {
    do {
      let profileArray = Array(profiles.values)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(profileArray)
      // Atomic so a crash or full disk mid-write can't truncate the store.
      try data.write(to: storageURL, options: .atomic)

      Logger.presets.debug("PlaybackProfileStore: Saved \(profileArray.count) profiles")
    } catch {
      Logger.presets.error(
        "PlaybackProfileStore: Failed to save profiles: \(error, privacy: .public)")
    }
  }
}
