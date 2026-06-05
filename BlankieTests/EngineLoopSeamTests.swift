//
//  EngineLoopSeamTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Accelerate
import XCTest

@testable import Blankie

/// Verifies that looping across a wrap introduces neither a click nor a silent
/// gap at the seam. Thresholds are self-referential (derived from the file's
/// own statistics) to avoid magic numbers.
final class EngineLoopSeamTests: XCTestCase {

  private func bundledSoundURL(_ name: String) throws -> URL {
    try XCTUnwrap(
      Bundle.main.url(forResource: name, withExtension: "m4a"),
      "Missing bundled sound \(name).m4a")
  }

  private func channelZero(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let data = buffer.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
  }

  /// Median absolute sample-to-sample delta — the file's "normal" step size.
  private func medianAbsDelta(_ samples: [Float]) -> Float {
    guard samples.count > 1 else { return 0 }
    var deltas = [Float]()
    deltas.reserveCapacity(samples.count - 1)
    for index in 1..<samples.count {
      deltas.append(abs(samples[index] - samples[index - 1]))
    }
    deltas.sort()
    let mid = deltas.count / 2
    return deltas.count % 2 == 1 ? deltas[mid] : (deltas[mid - 1] + deltas[mid]) / 2
  }

  func testFireplaceLoopSeamContinuity() throws {
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
    XCTAssertLessThan(seam, samples.count, "Render did not reach the seam frame")

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
    XCTAssertLessThan(
      maxJump, maxContentJump,
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
    XCTAssertLessThan(
      longestSilentRun, gapFrames,
      "Found \(longestSilentRun) frames (>5ms) of silence at the seam — a loop gap")
  }

  func testRainLoopSeamRMSContinuity() throws {
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
    XCTAssertGreaterThan(seam - window, 0)
    XCTAssertLessThan(seam + window, samples.count)

    func rmsDB(_ slice: ArraySlice<Float>) -> Float {
      let arr = Array(slice)
      var meanSquare: Float = 0
      vDSP_measqv(arr, 1, &meanSquare, vDSP_Length(arr.count))
      return 20 * log10(sqrt(meanSquare) + 1e-9)
    }

    let before = rmsDB(samples[(seam - window)..<seam])
    let after = rmsDB(samples[seam..<(seam + window)])
    XCTAssertLessThanOrEqual(
      abs(before - after), 6.0,
      "Rain loop seam RMS jumped \(abs(before - after)) dB (before \(before), after \(after))")
  }
}
