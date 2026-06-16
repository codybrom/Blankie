//
//  EngineLoopSeamTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Accelerate
import Testing

@testable import Blankie

/// Verifies that looping across a wrap introduces neither a click nor a silent
/// gap at the seam. Thresholds are self-referential (derived from the file's own
/// statistics) to avoid magic numbers. Serialized: each test renders audio
/// offline, so running them concurrently would multiply peak memory.
@Suite(.serialized) struct EngineLoopSeamTests {

  private func bundledSoundURL(_ name: String) throws -> URL {
    try #require(
      Bundle.main.url(forResource: name, withExtension: "m4a"),
      "Missing bundled sound \(name).m4a")
  }

  private func channelZero(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let data = buffer.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
  }

  @Test func fireplaceLoopSeamContinuity() async throws {
    let url = try bundledSoundURL("fireplace")
    let file = try AVAudioFile(forReading: url)
    let sampleRate = file.processingFormat.sampleRate
    let fileFrames = Int(file.length)
    let fileDuration = Double(fileFrames) / sampleRate

    // Render across one wrap (the harness loops by scheduling the file twice).
    let buffer = try EngineRenderHarness.render(
      fileURL: url, boostDB: 0, attenuation: 1.0,
      seconds: fileDuration + 2.0, throughLimiter: false)

    let samples = channelZero(buffer)
    let seam = fileFrames
    #expect(seam < samples.count, "Render did not reach the seam frame")

    let windowFrames = Int(0.010 * sampleRate)
    let start = max(1, seam - windowFrames)
    let end = min(samples.count, seam + windowFrames)

    var maxJump: Float = 0
    for index in start..<end {
      maxJump = max(maxJump, abs(samples[index] - samples[index - 1]))
    }

    // The seam is gapless if its jump is no worse than the file's own content
    // transients (fireplace crackles step far harder than any clean seam).
    var maxContentJump: Float = 0
    for index in 1..<samples.count where index < start || index >= end {
      maxContentJump = max(maxContentJump, abs(samples[index] - samples[index - 1]))
    }
    #expect(
      maxJump < maxContentJump,
      "Seam discontinuity \(maxJump) exceeds the file's own max content step \(maxContentJump)")

    // Gap detection: no >5ms run of pure silence straddling the seam.
    let silenceFloor: Float = 1e-4
    let gapFrames = Int(0.005 * sampleRate)
    var longestSilentRun = 0
    var currentRun = 0
    for index in start..<end {
      if abs(samples[index]) < silenceFloor {
        currentRun += 1
        longestSilentRun = max(longestSilentRun, currentRun)
      } else {
        currentRun = 0
      }
    }
    #expect(
      longestSilentRun < gapFrames,
      "Found \(longestSilentRun) frames (>5ms) of silence at the seam — a loop gap")
  }

  @Test func rainLoopSeamRMSContinuity() async throws {
    let url = try bundledSoundURL("rain")
    let file = try AVAudioFile(forReading: url)
    let sampleRate = file.processingFormat.sampleRate
    let fileFrames = Int(file.length)
    let fileDuration = Double(fileFrames) / sampleRate

    let buffer = try EngineRenderHarness.render(
      fileURL: url, boostDB: 0, attenuation: 1.0,
      seconds: fileDuration + 2.0, throughLimiter: false)

    let samples = channelZero(buffer)
    let seam = fileFrames
    let window = Int(0.030 * sampleRate)
    #expect(seam - window > 0)
    #expect(seam + window < samples.count)

    func rmsDB(_ slice: ArraySlice<Float>) -> Float {
      let arr = Array(slice)
      var meanSquare: Float = 0
      vDSP_measqv(arr, 1, &meanSquare, vDSP_Length(arr.count))
      return 20 * log10(sqrt(meanSquare) + 1e-9)
    }

    let before = rmsDB(samples[(seam - window)..<seam])
    let after = rmsDB(samples[seam..<(seam + window)])
    #expect(
      abs(before - after) <= 6.0,
      "Rain loop seam RMS jumped \(abs(before - after)) dB (before \(before), after \(after))")
  }
}
