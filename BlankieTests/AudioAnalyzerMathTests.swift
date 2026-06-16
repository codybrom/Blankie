//
//  AudioAnalyzerMathTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Pure loudness/gain math. A sign flip or a broken cap makes the whole library
//  too loud or over-amplifies noise. (The file-decoding analysis paths are
//  covered by EngineLoudnessTests; this covers the arithmetic directly.)
//

import Foundation
import Testing

@testable import Blankie

@Suite struct AudioAnalyzerMathTests {

  // MARK: - Peak normalization

  @Test func peakFactorReachesTargetAndCaps() {
    #expect(AudioAnalyzer.calculateNormalizationFactor(peakLevel: 0) == 1.0)  // silence untouched
    #expect(
      isClose(AudioAnalyzer.calculateNormalizationFactor(peakLevel: 0.4, targetLevel: 0.8), 2.0))
    // A very quiet peak would need 8x; capped at 3x so noise isn't amplified.
    #expect(AudioAnalyzer.calculateNormalizationFactor(peakLevel: 0.1, targetLevel: 0.8) == 3.0)
  }

  // MARK: - LUFS normalization (two-way, capped boost)

  @Test func lufsFactorBoostsQuietAttenuatesLoud() {
    // At target: no change.
    #expect(
      isClose(AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: AudioAnalyzer.targetLUFS), 1.0))
    // 3 dB quiet -> +3 dB boost = ~1.413x.
    #expect(isClose(AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: -30), 1.413, tol: 0.01))
    // Loud sound -> attenuation below 1.0 (uncapped, always safe).
    #expect(AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: -10) < 1.0)
  }

  @Test func lufsBoostIsCappedAndFloorIsRespected() {
    // 23 dB of boost requested, capped at maxGainDB (18 dB) = ~7.943x.
    let capped = AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: -50)
    #expect(isClose(capped, pow(10, AudioAnalyzer.maxGainDB / 20), tol: 0.01))
    // Below the minimum LUFS floor, treated as silence: left untouched.
    #expect(AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: -61) == 1.0)
  }

  // MARK: - dBFS conversions

  @Test func dBFSConversions() {
    let full = AudioAnalysisResult(
      lufs: nil, normalizationFactor: 1, peakLevel: 1.0, rmsLevel: 0.5,
      truePeakdBTP: nil, needsLimiter: false, duration: nil)
    #expect(isClose(full.peakdBFS ?? -99, 0.0, tol: 0.01))
    #expect(isClose(full.rmsdBFS ?? -99, -6.02, tol: 0.05))

    let silent = AudioAnalysisResult(
      lufs: nil, normalizationFactor: 1, peakLevel: 0, rmsLevel: 0,
      truePeakdBTP: nil, needsLimiter: false, duration: nil)
    #expect(silent.peakdBFS == nil)
    #expect(silent.rmsdBFS == nil)
  }

  // MARK: - PlaybackProfile.from gain + limiter

  private func analysis(lufs: Float?, truePeak: Float?) -> AudioAnalysisResult {
    AudioAnalysisResult(
      lufs: lufs, normalizationFactor: 1, peakLevel: nil, rmsLevel: nil,
      truePeakdBTP: truePeak, needsLimiter: false, duration: nil)
  }

  @Test func profileNeedsLimiterWhenBoostExceedsCeiling() {
    // 13 dB boost onto a -10 dBTP peak -> +3 dBTP, over the -1 ceiling.
    let p = PlaybackProfile.from(analysis: analysis(lufs: -40, truePeak: -10), filename: "x.m4a")
    let profile = try! #require(p)
    #expect(isClose(profile.gainDB, 13))
    #expect(profile.needsLimiter)
  }

  @Test func profileSkipsLimiterWithHeadroomAndCapsGain() {
    // Quiet enough to request >18 dB, but capped; peak stays well under ceiling.
    let p = PlaybackProfile.from(analysis: analysis(lufs: -50, truePeak: -30), filename: "x.m4a")
    let profile = try! #require(p)
    #expect(isClose(profile.gainDB, AudioAnalyzer.maxGainDB))
    #expect(!profile.needsLimiter)
  }

  @Test func profileNilWithoutAnalysisData() {
    #expect(
      PlaybackProfile.from(analysis: analysis(lufs: nil, truePeak: -10), filename: "x") == nil)
    #expect(
      PlaybackProfile.from(analysis: analysis(lufs: -30, truePeak: nil), filename: "x") == nil)
  }
}
