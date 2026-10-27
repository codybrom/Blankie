//
//  LongAudioArithmeticTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Frame and duration arithmetic at the edges uncapped imports can reach: 2^32+ frames,
//  non-finite durations and zero-width waveforms. The 2^32-frame fixture is a sparse CAF
//  that uses a few KB of disk.
//

import AVFoundation
import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor struct LongAudioArithmeticTests {

  /// 2^32 + 7 frames, a few frames past what UInt32 holds.
  private static let hugeFrameCount = (Int64(1) << 32) + 7

  /// Writes a sparse CAF reporting `hugeFrameCount` frames at 48 kHz.
  private func makeHugeCAF(in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("huge.caf")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 8, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true,
    ]
    do {
      let file = try AVAudioFile(forWriting: url, settings: settings)
      let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16))
      buffer.frameLength = 16
      try file.write(from: buffer)
    }

    // Mark the data chunk's size unknown (-1), so its length runs to end of
    // file, then extend the file sparsely.
    var data = try Data(contentsOf: url)
    let tag = try #require(data.range(of: Data("data".utf8)))
    for offset in 0..<8 { data[tag.upperBound + offset] = 0xFF }
    let audioStart = UInt64(tag.upperBound + 8 + 4)  // size, then mEditCount
    try data.write(to: url)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: audioStart + UInt64(Self.hugeFrameCount))
    try handle.close()
    return url
  }

  @Test func sparseFixtureReachesPastUInt32() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = try AVAudioFile(forReading: try makeHugeCAF(in: dir))
    #expect(file.length == Self.hugeFrameCount)
    #expect(AVAudioFrameCount(exactly: file.length) == nil)
  }

  // MARK: - 2^32+ frames

  /// A file too long for one buffer can't narrow to AVAudioFrameCount.
  @Test func wholeFileAnalysisDeclinesHugeFiles() async throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try makeHugeCAF(in: dir)

    #expect(await AudioAnalyzer.analyzePeakLevel(at: url) == nil)
    #expect(await AudioAnalyzer.analyzeRMSLevel(at: url) == nil)
  }

  /// The remaining frame count must be clamped before it narrows to AVAudioFrameCount.
  @Test func streamingSchedulesTheFirstChunkOfHugeFiles() throws {
    let dir = TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let player = try SoundPlayer(fileURL: try makeHugeCAF(in: dir), loops: false)
    guard case .streaming = player.mode else {
      Issue.record("A file this long should stream")
      return
    }

    let engine = AVAudioEngine()
    let format = player.file.processingFormat
    engine.attach(player.node)
    engine.attach(player.gain)
    engine.connect(player.node, to: player.gain, format: format)
    engine.connect(player.gain, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    defer {
      player.stop()
      engine.stop()
    }

    player.play(fromFrame: 0)

    let output = try #require(
      AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
    #expect(try engine.renderOffline(4096, to: output) == .success)
    #expect(player.isPlaying)
  }

  // MARK: - Non-finite durations

  /// A malformed file's duration can be infinite or too large for Int64(_:).
  @Test func compressionEstimateDeclinesNonFiniteDurations() {
    let manager = CustomSoundManager.shared
    let bytes: Int64 = 50 * 1024 * 1024
    for duration in [TimeInterval.infinity, .nan, 1e300] {
      #expect(
        manager.compressionEstimate(forExtension: "wav", currentBytes: bytes, duration: duration)
          == nil)
    }
    // A real long WAV still gets an estimate.
    #expect(
      manager.compressionEstimate(forExtension: "wav", currentBytes: bytes, duration: 60) != nil)
  }

  /// Int(_:) traps on non-finite or huge values.
  @Test func clockShowsAPlaceholderForNonFiniteIntervals() {
    for interval in [TimeInterval.infinity, -.infinity, .nan, 1e300, -1e300] {
      #expect(interval.minuteSecondClock == "--:--")
    }
    #expect(TimeInterval(185).minuteSecondClock == "3:05")
  }

  // MARK: - Zero-width waveform

  /// Under about 2 pt of width there's room for zero bars. Downsampling must not divide by zero.
  @Test func waveformDownsamplesToZeroBars() {
    #expect(SoundWaveformView.downsample([0.5, -0.25, 0.75], to: 0).isEmpty)
    #expect(SoundWaveformView.downsample([0.5, -0.25], to: 4) == [0.5, 0.25])
  }
}
