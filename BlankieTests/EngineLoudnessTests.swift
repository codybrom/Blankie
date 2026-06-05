//
//  EngineLoudnessTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import XCTest

@testable import Blankie

/// Verifies the planned engine graph drives sounds to the -27 LUFS target and
/// the limiter holds true peak under the ceiling. Renders offline via
/// EngineRenderHarness, measures with the production AudioAnalyzer overloads —
/// the same math gates production and tests.
final class EngineLoudnessTests: XCTestCase {

  private let targetLUFS: Float = -27.0
  private let renderSeconds: Double = 30.0

  // TEST_HOST = Blankie.app, so Bundle.main resolves bundled sounds exactly
  // the way Sound.getSoundURL() does.
  private func bundledSoundURL(_ name: String) throws -> URL {
    try XCTUnwrap(
      Bundle.main.url(forResource: name, withExtension: "m4a"),
      "Missing bundled sound \(name).m4a")
  }

  // MARK: - Loudness convergence

  /// The headline proof: fireplace (-42.89 LUFS source, factor 6.233) must
  /// come out of the graph at the target loudness. This is the bug.
  func testFireplaceRendersAtTargetLUFS() throws {
    let url = try bundledSoundURL("fireplace")
    let boostDB = 20 * log10(Float(6.233351))

    let buffer = try EngineRenderHarness.render(
      fileURL: url, boostDB: boostDB, attenuation: 1.0,
      seconds: renderSeconds, throughLimiter: false)

    let measured = try XCTUnwrap(AudioAnalyzer.integratedLUFS(buffer: buffer))
    XCTAssertEqual(
      measured, targetLUFS, accuracy: 0.5,
      "Fireplace should render near \(targetLUFS) LUFS, got \(measured)")
  }

  /// Boat is gain-capped at +18 dB (maxGainDB) from -49.85 LUFS, so it can
  /// only reach ≈ -31.85 — assert the capped target, not -27.
  func testBoatRendersAtGainCappedTarget() throws {
    let url = try bundledSoundURL("boat")
    let boostDB = 20 * log10(Float(7.943282))

    let buffer = try EngineRenderHarness.render(
      fileURL: url, boostDB: boostDB, attenuation: 1.0,
      seconds: renderSeconds, throughLimiter: false)

    let measured = try XCTUnwrap(AudioAnalyzer.integratedLUFS(buffer: buffer))
    let cappedTarget = Float(-49.852524) + 18.0
    XCTAssertEqual(
      measured, cappedTarget, accuracy: 0.5,
      "Boat (gain-capped) should render near \(cappedTarget) LUFS, got \(measured)")
  }

  /// Attenuation path: storm (factor 0.347 < 1) lands on target via node
  /// volume. Also answers empirically whether player-node volume applies when
  /// the node feeds an EQ rather than a mixer directly.
  func testStormAttenuatesToTarget() throws {
    let url = try bundledSoundURL("storm")
    let buffer = try EngineRenderHarness.render(
      fileURL: url, boostDB: 0, attenuation: Float(0.34659564),
      seconds: renderSeconds, throughLimiter: false)

    let measured = try XCTUnwrap(AudioAnalyzer.integratedLUFS(buffer: buffer))
    XCTAssertEqual(
      measured, targetLUFS, accuracy: 0.5,
      "Storm should attenuate to ≈ \(targetLUFS) LUFS, got \(measured)")
  }

  // MARK: - True-peak ceiling with limiter

  func testTruePeakStaysUnderCeilingWithLimiter() throws {
    let url = try bundledSoundURL("fireplace")
    let boostDB = 20 * log10(Float(6.233351))

    let buffer: AVAudioPCMBuffer
    do {
      buffer = try EngineRenderHarness.render(
        fileURL: url, boostDB: boostDB, attenuation: 1.0,
        seconds: renderSeconds, throughLimiter: true)
    } catch EngineRenderError.limiterUnavailable(let status) {
      throw XCTSkip(
        "PeakLimiter AU unavailable in manual rendering (OSStatus \(status)); "
          + "verify limiter behavior on a real build (flagged unknown #1).")
    }

    // The PeakLimiter AU's ceiling is 0 dBFS (no ceiling parameter exists);
    // for live playback the requirement is no digital clipping, and without
    // the limiter this signal would hit ≈ +14.8 dBTP.
    let truePeak = try XCTUnwrap(AudioAnalyzer.truePeakdBTP(buffer: buffer))
    XCTAssertLessThanOrEqual(
      truePeak, 0.1,
      "Limiter should prevent digital clipping (ceiling ≈ 0 dBFS), got \(truePeak) dBTP")
  }

  // MARK: - Synthesized quiet tone (the quiet-custom-import case)

  /// Self-referential: measure the synthesized file, derive the boost the app
  /// would apply (clamped to maxGainDB), assert the render lands accordingly.
  func testSynthesizedQuietToneBoosts() throws {
    let url = try Self.makeQuietToneURL(channels: 2)
    defer { try? FileManager.default.removeItem(at: url) }

    let (measuredIn, measuredOut, boostDB) = try Self.boostRoundTrip(url, target: targetLUFS)
    let expected = min(measuredIn + boostDB, targetLUFS)
    // Looser tolerance: AAC round-trip + offline render drift.
    XCTAssertEqual(
      measuredOut, expected, accuracy: 0.75,
      "Boosted synthesized tone should land near \(expected) LUFS, got \(measuredOut)")
  }

  /// MONO sources lose ≈3 dB through the mixer (constant-power pan law on
  /// mono inputs). This test documents that behavior so Stage 3 knows to
  /// compensate mono customs (+3 dB or upmix at decode). Built-ins are stereo.
  func testMonoSourceRendersThreeDBLow() throws {
    let url = try Self.makeQuietToneURL(channels: 1)
    defer { try? FileManager.default.removeItem(at: url) }

    let (measuredIn, measuredOut, boostDB) = try Self.boostRoundTrip(url, target: targetLUFS)
    let expected = min(measuredIn + boostDB, targetLUFS) - 3.0
    XCTAssertEqual(
      measuredOut, expected, accuracy: 0.75,
      "Mono source should land ≈3 dB under \(expected + 3.0) LUFS, got \(measuredOut)")
  }

  /// Shared probe → boost → render → measure round trip.
  private static func boostRoundTrip(
    _ url: URL, target: Float
  ) throws -> (measuredIn: Float, measuredOut: Float, boostDB: Float) {
    let probe = try AVAudioFile(forReading: url)
    let probeBuffer = try XCTUnwrap(
      AVAudioPCMBuffer(
        pcmFormat: probe.processingFormat, frameCapacity: AVAudioFrameCount(probe.length)))
    try probe.read(into: probeBuffer)

    let measuredIn = try XCTUnwrap(AudioAnalyzer.integratedLUFS(buffer: probeBuffer))
    let boostDB = min(target - measuredIn, AudioAnalyzer.maxGainDB)

    // 8s = exactly the two scheduled passes of the 4s fixture (no silent tail
    // to skew gating).
    let out = try EngineRenderHarness.render(
      fileURL: url, boostDB: boostDB, attenuation: 1.0,
      seconds: 8.0, throughLimiter: false)

    let measuredOut = try XCTUnwrap(AudioAnalyzer.integratedLUFS(buffer: out))
    return (measuredIn, measuredOut, boostDB)
  }

  // MARK: - Fixtures

  /// Writes a short, deterministic low-level sine tone to a temp .m4a using
  /// the same AAC settings blankifi's writeM4A uses. Ships nothing.
  private static func makeQuietToneURL(channels: UInt32) throws -> URL {
    let sampleRate = 44_100.0
    let seconds = 4.0
    let frameCount = Int(sampleRate * seconds)
    let amplitude: Float = 0.02
    let frequency: Float = 220.0

    var samples = [Float](repeating: 0, count: frameCount)
    for index in 0..<frameCount {
      let phase = 2.0 * Float.pi * frequency * Float(index) / Float(sampleRate)
      samples[index] = amplitude * sin(phase)
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("blankie-quiet-tone-\(UUID().uuidString).m4a")

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channels,
      AVEncoderBitRateKey: 192_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCount)))
    buffer.frameLength = AVAudioFrameCount(frameCount)
    samples.withUnsafeBufferPointer { src in
      for channel in 0..<Int(file.processingFormat.channelCount) {
        buffer.floatChannelData![channel].update(from: src.baseAddress!, count: frameCount)
      }
    }
    try file.write(from: buffer)
    return url
  }
}
