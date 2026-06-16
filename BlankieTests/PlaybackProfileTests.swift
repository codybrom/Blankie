//
//  PlaybackProfileTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Cached loudness analysis used at playback. Codable drift here means a sound
//  loads with the wrong gain; the targets must match the analyzer's constants.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct PlaybackProfileTests {

  private func makeProfile() -> PlaybackProfile {
    PlaybackProfile(
      filename: "rain.m4a",
      fileHash: "abc123",
      integratedLUFS: -23.0,
      truePeakdBTP: -2.0,
      gainDB: 3.5,
      needsLimiter: true)
  }

  @Test func initDerivesIdAndVersion() {
    let p = makeProfile()
    #expect(p.id == "rain.m4a")
    #expect(p.filename == "rain.m4a")
    #expect(p.analysisVersion == "1.0")
  }

  /// Targets are fixed references the gain math depends on.
  @Test func targetsMatchAnalyzerConstants() {
    let p = makeProfile()
    #expect(isClose(p.targetTruePeak, -1.0))
    #expect(isClose(p.targetLUFS, AudioAnalyzer.targetLUFS))
  }

  @Test func codableRoundTripPreservesFields() throws {
    let original = makeProfile()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PlaybackProfile.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.filename == original.filename)
    #expect(decoded.fileHash == original.fileHash)
    #expect(isClose(decoded.integratedLUFS, original.integratedLUFS))
    #expect(isClose(decoded.truePeakdBTP, original.truePeakdBTP))
    #expect(isClose(decoded.gainDB, original.gainDB))
    #expect(decoded.needsLimiter == original.needsLimiter)
    #expect(decoded.analysisVersion == original.analysisVersion)
  }

  // MARK: - Gain math (must mirror AudioAnalyzer exactly)

  private func analysis(lufs: Float, truePeak: Float = -30) -> AudioAnalysisResult {
    AudioAnalysisResult(
      lufs: lufs, normalizationFactor: 0, peakLevel: nil, rmsLevel: nil,
      truePeakdBTP: truePeak, needsLimiter: false, duration: nil)
  }

  /// A near-silent import (below the analyzer's minimumLUFS floor) must get
  /// UNITY gain. Regression guard: `from` previously skipped the floor and
  /// produced +18 dB, so a cached profile slammed amplified hiss at the user.
  @Test func fromFloorsSubMinimumLUFSToUnityGain() throws {
    let profile = try #require(
      PlaybackProfile.from(analysis: analysis(lufs: -65, truePeak: -40), filename: "hiss.m4a"))
    #expect(isClose(profile.gainDB, 0))
    #expect(!profile.needsLimiter)
  }

  /// The exact floor boundary: minimumLUFS itself is NOT boosted (guard is `>`).
  @Test func fromFloorBoundaryMatchesAnalyzer() throws {
    let atFloor = try #require(
      PlaybackProfile.from(analysis: analysis(lufs: AudioAnalyzer.minimumLUFS), filename: "f.m4a"))
    #expect(isClose(atFloor.gainDB, 0))
    #expect(
      isClose(AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: AudioAnalyzer.minimumLUFS), 1.0))
  }

  /// Quiet (but real) sounds boost, capped at maxGainDB rather than the raw +23.
  @Test func fromBoostsQuietCappedAtMaxGain() throws {
    let profile = try #require(
      PlaybackProfile.from(analysis: analysis(lufs: -50), filename: "quiet.m4a"))
    #expect(isClose(profile.gainDB, AudioAnalyzer.maxGainDB))
  }

  /// Loud sounds attenuate (negative gain toward target).
  @Test func fromAttenuatesLoud() throws {
    let profile = try #require(
      PlaybackProfile.from(analysis: analysis(lufs: -10), filename: "loud.m4a"))
    #expect(isClose(profile.gainDB, AudioAnalyzer.targetLUFS - (-10)))  // -17 dB
  }

  /// The profile's linear gain must equal the analyzer's factor at EVERY LUFS,
  /// including across the sub-floor region where the two used to diverge.
  @Test func fromLinearGainMatchesAnalyzerAcrossRange() throws {
    for lufs in [Float(-70), -61, -60, -59, -45, -27, -12] {
      let profile = try #require(
        PlaybackProfile.from(analysis: analysis(lufs: lufs), filename: "s.m4a"))
      let profileFactor = Float(pow(10.0, Double(profile.gainDB) / 20.0))
      #expect(
        isClose(
          profileFactor, AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: lufs), tol: 1e-3),
        "profile gain diverged from analyzer at \(lufs) LUFS")
    }
  }
}
