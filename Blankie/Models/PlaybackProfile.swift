//
//  PlaybackProfile.swift
//  Blankie
//
//  Created by Cody Bromley on 6/5/25.
//

import Foundation

/// Stores pre-computed loudness analysis results for efficient playback
struct PlaybackProfile: Codable, Equatable {
  let id: String  // Unique identifier (filename or hash)
  let filename: String
  let fileHash: String?  // Optional hash to detect file changes
  let integratedLUFS: Float
  let truePeakdBTP: Float
  let gainDB: Float  // Pre-calculated gain to apply
  let needsLimiter: Bool
  let analysisDate: Date
  let analysisVersion: String  // Track which version of analysis was used

  // Computed properties
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

    // Calculate gain needed to reach target LUFS
    let targetLUFS = AudioAnalyzer.targetLUFS
    let gainDB = targetLUFS - lufs

    // Check if applying gain would exceed true peak limit
    let predictedTruePeak = truePeak + gainDB
    let targetTruePeak: Float = -1.0  // -1 dBTP

    // Adjust gain if needed to prevent clipping
    let finalGainDB: Float
    let needsLimiter: Bool

    if predictedTruePeak > targetTruePeak {
      // Option 1: Reduce gain to stay under limit
      // finalGainDB = targetTruePeak - truePeak
      // Option 2: Apply full gain but flag for limiter
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

/// Manages persistence of playback profiles
class PlaybackProfileStore {
  static let shared = PlaybackProfileStore()

  private let storageURL: URL = {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let blankieDir = appSupport.appendingPathComponent("Blankie", isDirectory: true)

    // Create directory if needed
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

  /// Get a profile for a filename
  func profile(for filename: String) -> PlaybackProfile? {
    queue.sync {
      profiles[filename]
    }
  }

  /// Store a profile
  func store(_ profile: PlaybackProfile) {
    queue.async(flags: .barrier) {
      self.profiles[profile.filename] = profile
      self.saveProfiles()
    }
  }

  /// Store multiple profiles at once
  func store(_ newProfiles: [PlaybackProfile]) {
    queue.async(flags: .barrier) {
      for profile in newProfiles {
        self.profiles[profile.filename] = profile
      }
      self.saveProfiles()
    }
  }

  /// Remove a profile
  func removeProfile(for filename: String) {
    queue.async(flags: .barrier) {
      self.profiles.removeValue(forKey: filename)
      self.saveProfiles()
    }
  }

  /// Check if a profile needs updating (file changed)
  func needsUpdate(filename: String, fileHash: String?) -> Bool {
    guard let existingProfile = profile(for: filename) else {
      return true  // No profile exists
    }

    // If we have hashes, compare them
    if let existingHash = existingProfile.fileHash,
      let newHash = fileHash
    {
      return existingHash != newHash
    }

    // Otherwise, can't determine if update is needed
    return false
  }

  // MARK: - Private Methods

  private func loadProfiles() {
    guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

    do {
      let data = try Data(contentsOf: storageURL)
      let decodedProfiles = try JSONDecoder().decode([PlaybackProfile].self, from: data)

      // Convert array to dictionary for fast lookup
      for profile in decodedProfiles {
        profiles[profile.filename] = profile
      }

      debugLog("🎵 PlaybackProfileStore: Loaded \(profiles.count) profiles")
    } catch {
      debugLog("❌ PlaybackProfileStore: Failed to load profiles: \(error)")
    }
  }

  private func saveProfiles() {
    do {
      let profileArray = Array(profiles.values)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(profileArray)
      try data.write(to: storageURL)

      debugLog("💾 PlaybackProfileStore: Saved \(profileArray.count) profiles")
    } catch {
      debugLog("❌ PlaybackProfileStore: Failed to save profiles: \(error)")
    }
  }
}
