//
//  EngineLoudnessTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Testing

@testable import Blankie

/// Verifies the planned engine graph drives sounds to the -27 LUFS target and
/// the limiter holds true peak under the ceiling. Renders offline via
/// EngineRenderHarness, measures with the production AudioAnalyzer overloads —
/// the same math gates production and tests. Serialized: offline renders are
/// memory-heavy and shouldn't run concurrently.
@Suite(.serialized) struct EngineLoudnessTests {

  private let targetLUFS = AudioAnalyzer.targetLUFS
  private let renderSeconds: Double = 30.0

  // TEST_HOST = Blankie.app, so Bundle.main resolves bundled sounds exactly
  // the way Sound.getSoundURL() does.
  private func bundledSoundURL(_ name: String) throws -> URL {
    try #require(
      Bundle.main.url(forResource: name, withExtension: "m4a"),
      "Missing bundled sound \(name).m4a")
  }

  /// The shipped normalization data for a built-in sound, read from sounds.json
  /// — the same source the app loads. Reading it (rather than hardcoding factors)
  /// keeps these tests passing across recuts, and makes them fail loudly if a
  /// sound is recut without regenerating its factor.
  private func soundData(_ fileName: String) throws -> SoundData {
    let url = try #require(
      Bundle.main.url(forResource: "sounds", withExtension: "json"),
      "sounds.json missing from bundle")
    let container = try JSONDecoder().decode(SoundsContainer.self, from: Data(contentsOf: url))
    return try #require(
      container.sounds.first { $0.fileName == fileName }, "\(fileName) missing from sounds.json")
  }

  // MARK: - Loudness convergence

  /// The headline proof: applying fireplace's shipped normalization factor must
  /// bring it out of the graph at the target loudness.
  @Test func fireplaceRendersAtTargetLUFS() async throws {
    let factor = try #require(soundData("fireplace").normalizationFactor)

    let buffer = try EngineRenderHarness.render(
      fileURL: try bundledSoundURL("fireplace"), boostDB: 20 * log10(factor), attenuation: 1.0,
      seconds: renderSeconds, throughLimiter: false)

    let measured = try #require(AudioAnalyzer.integratedLUFS(buffer: buffer))
    #expect(
      abs(measured - targetLUFS) <= 0.5,
      "Fireplace's shipped normalization should render near \(targetLUFS) LUFS, got \(measured)")
  }

  /// Boat is too quiet to reach the target within the gain cap, so it lands at
  /// source + maxGainDB rather than the target. Values from sounds.json.
  @Test func boatRendersAtGainCappedTarget() async throws {
    let sound = try soundData("boat")
    let factor = try #require(sound.normalizationFactor)
    let sourceLUFS = try #require(sound.lufs)

    let buffer = try EngineRenderHarness.render(
      fileURL: try bundledSoundURL("boat"), boostDB: 20 * log10(factor), attenuation: 1.0,
      seconds: renderSeconds, throughLimiter: false)

    let measured = try #require(AudioAnalyzer.integratedLUFS(buffer: buffer))
    let cappedTarget = sourceLUFS + AudioAnalyzer.maxGainDB
    #expect(
      abs(measured - cappedTarget) <= 0.5,
      "Boat (gain-capped) should render near \(cappedTarget) LUFS, got \(measured)")
  }

  /// Attenuation path: storm's factor is < 1, applied as node-volume attenuation
  /// (not EQ gain), and must land on target. Factor from sounds.json.
  @Test func stormAttenuatesToTarget() async throws {
    let factor = try #require(soundData("storm").normalizationFactor)

    let buffer = try EngineRenderHarness.render(
      fileURL: try bundledSoundURL("storm"), boostDB: 0, attenuation: factor,
      seconds: renderSeconds, throughLimiter: false)

    let measured = try #require(AudioAnalyzer.integratedLUFS(buffer: buffer))
    #expect(
      abs(measured - targetLUFS) <= 0.5,
      "Storm should attenuate to ≈ \(targetLUFS) LUFS, got \(measured)")
  }

  // MARK: - True-peak ceiling with limiter

  @Test func truePeakStaysUnderCeilingWithLimiter() async throws {
    let factor = try #require(soundData("fireplace").normalizationFactor)

    let buffer: AVAudioPCMBuffer
    do {
      buffer = try EngineRenderHarness.render(
        fileURL: try bundledSoundURL("fireplace"), boostDB: 20 * log10(factor), attenuation: 1.0,
        seconds: renderSeconds, throughLimiter: true)
    } catch EngineRenderError.limiterUnavailable(let status) {
      try Test.cancel(
        "PeakLimiter AU unavailable in manual rendering (OSStatus \(status)); verify limiter behavior on a real build (flagged unknown #1)."
      )
    }

    // The PeakLimiter AU's ceiling is 0 dBFS (no ceiling parameter exists); for
    // live playback the requirement is no digital clipping, and without the
    // limiter this signal would hit ≈ +14.8 dBTP.
    let truePeak = try #require(AudioAnalyzer.truePeakdBTP(buffer: buffer))
    #expect(
      truePeak <= 0.1,
      "Limiter should prevent digital clipping (ceiling ≈ 0 dBFS), got \(truePeak) dBTP")
  }

  // MARK: - Synthesized quiet tone (the quiet-custom-import case)

  /// Self-referential: measure the synthesized file, derive the boost the app
  /// would apply (clamped to maxGainDB), assert the render lands accordingly.
  @Test func synthesizedQuietToneBoosts() async throws {
    let url = try Self.makeQuietToneURL(channels: 2)
    defer { try? FileManager.default.removeItem(at: url) }

    let (measuredIn, measuredOut, boostDB) = try Self.boostRoundTrip(url, target: targetLUFS)
    let expected = min(measuredIn + boostDB, targetLUFS)
    // Looser tolerance: AAC round-trip + offline render drift.
    #expect(
      abs(measuredOut - expected) <= 0.75,
      "Boosted synthesized tone should land near \(expected) LUFS, got \(measuredOut)")
  }

  /// MONO sources lose ≈3 dB through the mixer (constant-power pan law on mono
  /// inputs). This test documents that behavior so Stage 3 knows to compensate
  /// mono customs (+3 dB or upmix at decode). Built-ins are stereo.
  @Test func monoSourceRendersThreeDBLow() async throws {
    let url = try Self.makeQuietToneURL(channels: 1)
    defer { try? FileManager.default.removeItem(at: url) }

    let (measuredIn, measuredOut, boostDB) = try Self.boostRoundTrip(url, target: targetLUFS)
    let expected = min(measuredIn + boostDB, targetLUFS) - 3.0
    #expect(
      abs(measuredOut - expected) <= 0.75,
      "Mono source should land ≈3 dB under \(expected + 3.0) LUFS, got \(measuredOut)")
  }

  /// Shared probe → boost → render → measure round trip.
  private static func boostRoundTrip(
    _ url: URL, target: Float
  ) throws -> (measuredIn: Float, measuredOut: Float, boostDB: Float) {
    let probe = try AVAudioFile(forReading: url)
    let probeBuffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: probe.processingFormat, frameCapacity: AVAudioFrameCount(probe.length)))
    try probe.read(into: probeBuffer)

    let measuredIn = try #require(AudioAnalyzer.integratedLUFS(buffer: probeBuffer))
    let boostDB = min(target - measuredIn, AudioAnalyzer.maxGainDB)

    // 8s = exactly the two scheduled passes of the 4s fixture (no silent tail
    // to skew gating).
    let out = try EngineRenderHarness.render(
      fileURL: url, boostDB: boostDB, attenuation: 1.0,
      seconds: 8.0, throughLimiter: false)

    let measuredOut = try #require(AudioAnalyzer.integratedLUFS(buffer: out))
    return (measuredIn, measuredOut, boostDB)
  }

  // MARK: - Fixtures

  /// Writes a short, deterministic low-level sine tone to a temp .m4a using the
  /// same AAC settings blankifi's writeM4A uses. Ships nothing.
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
    let buffer = try #require(
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
