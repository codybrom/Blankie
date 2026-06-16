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
}
