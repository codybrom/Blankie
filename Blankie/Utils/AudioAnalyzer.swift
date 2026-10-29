//
//  AudioAnalyzer.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate
import os

struct AudioAnalysisResult: Sendable {
  let lufs: Float?
  let normalizationFactor: Float
  let peakLevel: Float?
  let rmsLevel: Float?
  let truePeakdBTP: Float?
  let needsLimiter: Bool
  let duration: TimeInterval?
  var peakdBFS: Float? {
    guard let peak = peakLevel, peak > 0 else { return nil }
    return 20 * log10(peak)
  }

  var rmsdBFS: Float? {
    guard let rms = rmsLevel, rms > 0 else { return nil }
    return 20 * log10(rms)
  }
}

/// Stateless audio analysis. `nonisolated` keeps the DSP off the main actor, and
/// the `@concurrent` async entry points run on the background pool from any caller.
nonisolated class AudioAnalyzer {
  // MARK: - LUFS Configuration

  static let targetLUFS: Float = -27.0

  /// Below this LUFS a sound is left un-normalized (treated as silence/noise).
  /// Kept well under the quietest built-in sound (boat, about -49.85 LUFS).
  static let minimumLUFS: Float = -60.0

  /// Caps the normalization boost. Attenuation is uncapped.
  static let maxGainDB: Float = 18.0

  /// Frames per read for the file-level passes. Imports have no length cap, so a
  /// whole-file buffer can run to gigabytes (#144).
  static let analysisChunkFrames: AVAudioFrameCount = 48000

  /// Peak sample magnitude (0 to 1), or nil if the file can't be read.
  @concurrent static func analyzePeakLevel(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: analysisChunkFrames)
      else {
        Logger.app.error("AudioAnalyzer: Failed to create buffer")
        return nil
      }

      var peakLevel: Float = 0.0

      while file.framePosition < file.length {
        try file.read(into: buffer, frameCount: analysisChunkFrames)
        guard buffer.frameLength > 0 else { break }

        for channel in 0..<Int(format.channelCount) {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }
          var channelPeak: Float = 0
          vDSP_maxmgv(channelData, 1, &channelPeak, vDSP_Length(buffer.frameLength))
          peakLevel = max(peakLevel, channelPeak)
        }
      }

      Logger.app.debug("AudioAnalyzer: Peak level for \(url.lastPathComponent): \(peakLevel)")
      return peakLevel

    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze audio file: \(error, privacy: .public)")
      return nil
    }
  }

  /// Peak-based normalization factor toward `targetLevel` (0.8 leaves headroom).
  static func calculateNormalizationFactor(peakLevel: Float, targetLevel: Float = 0.8) -> Float {
    guard peakLevel > 0 else { return 1.0 }

    let factor = targetLevel / peakLevel

    // Max 3x gain (9.5 dB) so quiet files don't amplify noise.
    let limitedFactor = min(factor, 3.0)

    Logger.app.debug(
      "AudioAnalyzer: Peak normalization factor: \(limitedFactor) (peak: \(peakLevel), target: \(targetLevel))"
    )
    return limitedFactor
  }

  /// Linear gain that moves integrated `lufs` toward `targetLUFS`.
  static func calculateLUFSNormalizationFactor(lufs: Float) -> Float {
    // Leave sounds too quiet to be real signal untouched.
    guard lufs > minimumLUFS else { return 1.0 }

    // Two-way match: quiet sounds are boosted and loud ones attenuated, so built-in
    // and custom sounds land at the same level. Only the boost is capped. The soft
    // limiter catches residual clipping.
    let requiredGainDB = targetLUFS - lufs
    let limitedGainDB = min(requiredGainDB, maxGainDB)

    return pow(10, limitedGainDB / 20)
  }

  /// Mean per-channel RMS level (0 to 1), or nil if the file can't be read.
  @concurrent static func analyzeRMSLevel(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: analysisChunkFrames)
      else {
        return nil
      }

      let channelCount = Int(format.channelCount)
      // Double, since a Float sum over hours of samples stops absorbing small terms.
      var squaredSums = [Double](repeating: 0, count: channelCount)
      var framesRead: Int64 = 0

      while file.framePosition < file.length {
        try file.read(into: buffer, frameCount: analysisChunkFrames)
        guard buffer.frameLength > 0 else { break }

        for channel in 0..<channelCount {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }
          var squaredSum: Float = 0
          vDSP_svesq(channelData, 1, &squaredSum, vDSP_Length(buffer.frameLength))
          squaredSums[channel] += Double(squaredSum)
        }
        framesRead += Int64(buffer.frameLength)
      }

      guard framesRead > 0, channelCount > 0 else { return nil }

      let totalRMS = squaredSums.reduce(Float(0)) { total, sum in
        total + Float(sqrt(sum / Double(framesRead)))
      }
      let averageRMS = totalRMS / Float(channelCount)

      Logger.app.debug("AudioAnalyzer: RMS level for \(url.lastPathComponent): \(averageRMS)")
      return averageRMS

    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze RMS: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - Comprehensive Analysis

  /// Runs LUFS, peak, RMS, true peak and duration analysis and picks the
  /// normalization factor (LUFS first, peak as the fallback). `progress` receives the
  /// fraction decoded, from 0 to 1.
  @concurrent static func comprehensiveAnalysis(
    at url: URL, progress: (@Sendable (Double) -> Void)? = nil
  ) async -> AudioAnalysisResult {
    Logger.app.debug("AudioAnalyzer: Starting comprehensive analysis for \(url.lastPathComponent)")

    let levels = measureLevels(at: url, progress: progress)
    let peakLevel = levels?.peak
    let rmsLevel = levels?.rms
    let truePeakdBTP = levels?.truePeakdBTP
    let lufsResult = levels?.lufs.map {
      (lufs: $0, normalizationFactor: calculateLUFSNormalizationFactor(lufs: $0))
    }

    let duration = getDuration(at: url)

    let normalizationFactor: Float
    var needsLimiter = false

    if let lufsData = lufsResult {
      normalizationFactor = lufsData.normalizationFactor

      // The limiter is needed when the applied gain (after caps) would push true
      // peak above -1 dBTP, which only a boost can do.
      if let truePeak = truePeakdBTP {
        let appliedGainDB = 20 * log10(normalizationFactor)
        let predictedTruePeak = truePeak + appliedGainDB
        needsLimiter = predictedTruePeak > -1.0

        if needsLimiter {
          Logger.app.debug(
            "AudioAnalyzer: Limiter needed - predicted peak: \(predictedTruePeak) dBTP")
        }
      }
    } else if let peak = peakLevel {
      normalizationFactor = calculateNormalizationFactor(peakLevel: peak)
      Logger.app.debug("AudioAnalyzer: Using peak-based normalization as fallback")
    } else {
      normalizationFactor = 1.0
    }

    return AudioAnalysisResult(
      lufs: lufsResult?.lufs,
      normalizationFactor: normalizationFactor,
      peakLevel: peakLevel,
      rmsLevel: rmsLevel,
      truePeakdBTP: truePeakdBTP,
      needsLimiter: needsLimiter,
      duration: duration
    )
  }

  /// The levels `comprehensiveAnalysis` needs, from one sequential decode.
  private struct Levels {
    let peak: Float
    let rms: Float?
    let truePeakdBTP: Float
    let lufs: Float?
  }

  /// Measures peak, RMS, true peak and integrated LUFS in one pass. The chunks match
  /// the single-measurement functions above, so each value matches theirs. Returns nil
  /// if the task is cancelled.
  private static func measureLevels(
    at url: URL, progress: (@Sendable (Double) -> Void)?
  ) -> Levels? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let channelCount = Int(format.channelCount)
      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: analysisChunkFrames)
      else {
        return nil
      }

      let filterCoefficients = getKWeightingCoefficients()
      var peak: Float = 0
      var truePeakMeters = [TruePeakMeter](repeating: TruePeakMeter(), count: channelCount)
      var squaredSums = [Double](repeating: 0, count: channelCount)
      var framesRead: Int64 = 0
      var loudnessMeasurements: [Float] = []
      // Report about every 1%, so the UI isn't flooded on long files.
      let reportEvery = max(1, file.length / 100)
      var nextReport: Int64 = 0

      while file.framePosition < file.length {
        if Task.isCancelled { return nil }
        if let progress, framesRead >= nextReport {
          progress(Double(framesRead) / Double(file.length))
          nextReport = framesRead + reportEvery
        }
        try file.read(into: buffer, frameCount: analysisChunkFrames)
        let frameLength = buffer.frameLength
        guard frameLength > 0 else { break }

        for channel in 0..<channelCount {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }
          var channelPeak: Float = 0
          vDSP_maxmgv(channelData, 1, &channelPeak, vDSP_Length(frameLength))
          peak = max(peak, channelPeak)

          var squaredSum: Float = 0
          vDSP_svesq(channelData, 1, &squaredSum, vDSP_Length(frameLength))
          squaredSums[channel] += Double(squaredSum)

          truePeakMeters[channel].process(channelData, count: Int(frameLength))
        }

        if let loudness = processAudioChunk(
          buffer, channelCount: format.channelCount, filterCoefficients: filterCoefficients)
        {
          loudnessMeasurements.append(loudness)
        }
        framesRead += Int64(frameLength)
      }

      var rms: Float?
      if framesRead > 0, channelCount > 0 {
        let totalRMS = squaredSums.reduce(Float(0)) { total, sum in
          total + Float(sqrt(sum / Double(framesRead)))
        }
        rms = totalRMS / Float(channelCount)
      }

      for channel in truePeakMeters.indices { truePeakMeters[channel].finish() }
      let truePeak = truePeakMeters.map(\.peak).max() ?? 0

      return Levels(
        peak: peak,
        rms: rms,
        truePeakdBTP: truePeak > 0 ? 20 * log10(truePeak) : -Float.infinity,
        lufs: calculateIntegratedLUFS(from: loudnessMeasurements))
    } catch {
      Logger.app.error("AudioAnalyzer: Failed to measure levels: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - Buffer-Based Analysis

  /// True-peak meter from ITU-R BS.1770 Annex 2: 4x oversampling through the standard's
  /// 48-tap polyphase interpolation filter. Use one per channel and feed it chunks in
  /// order, since the filter history carries across them.
  nonisolated private struct TruePeakMeter {
    /// The Annex 2 coefficients, one row per phase, reversed so `vDSP_conv`
    /// (a correlation) computes the convolution.
    private static let reversedPhases: [[Float]] = [
      [
        0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000,
        -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750,
        0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500,
      ],
      [
        -0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250,
        -0.1665039062500, 0.4650878906250, 0.7797851562500, -0.2003173828125,
        0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375,
      ],
      [
        -0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000,
        -0.2003173828125, 0.7797851562500, 0.4650878906250, -0.1665039062500,
        0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875,
      ],
      [
        -0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750,
        -0.1022949218750, 0.9721679687500, 0.1373291015625, -0.0594482421875,
        0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750,
      ],
    ].map { $0.reversed() }
    private static let tapCount = 12

    /// The largest magnitude seen, never below the sample peak.
    private(set) var peak: Float = 0
    private var history = [Float](repeating: 0, count: tapCount - 1)
    private var input: [Float] = []
    private var output: [Float] = []

    mutating func process(_ samples: UnsafePointer<Float>, count: Int) {
      guard count > 0 else { return }
      var samplePeak: Float = 0
      vDSP_maxmgv(samples, 1, &samplePeak, vDSP_Length(count))
      peak = max(peak, samplePeak)

      input.removeAll(keepingCapacity: true)
      input.append(contentsOf: history)
      input.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
      if output.count < count { output = [Float](repeating: 0, count: count) }

      input.withUnsafeBufferPointer { input in
        output.withUnsafeMutableBufferPointer { output in
          for taps in Self.reversedPhases {
            taps.withUnsafeBufferPointer { taps in
              vDSP_conv(
                input.baseAddress!, 1, taps.baseAddress!, 1, output.baseAddress!, 1,
                vDSP_Length(count), vDSP_Length(Self.tapCount))
            }
            var phasePeak: Float = 0
            vDSP_maxmgv(output.baseAddress!, 1, &phasePeak, vDSP_Length(count))
            peak = max(peak, phasePeak)
          }
        }
      }
      history = Array(input.suffix(Self.tapCount - 1))
    }

    /// Runs the filter tail so peaks between the final samples are measured.
    mutating func finish() {
      let silence = [Float](repeating: 0, count: Self.tapCount - 1)
      silence.withUnsafeBufferPointer { process($0.baseAddress!, count: $0.count) }
    }
  }

  /// Integrated LUFS of an in-memory buffer, reusing the exact chunk pipeline
  /// from the file path (filter state resets per 48k-frame chunk there too).
  static func integratedLUFS(buffer: AVAudioPCMBuffer) -> Float? {
    let channelCount = buffer.format.channelCount
    guard channelCount > 0, buffer.frameLength > 0,
      let channelPointers = buffer.floatChannelData
    else { return nil }

    let filterCoefficients = getKWeightingCoefficients()
    let chunkSize: AVAudioFrameCount = 48000
    var measurements: [Float] = []
    var position: AVAudioFrameCount = 0

    while position < buffer.frameLength {
      let framesInChunk = min(chunkSize, buffer.frameLength - position)

      guard
        let chunk = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: framesInChunk),
        let chunkPointers = chunk.floatChannelData
      else {
        position += framesInChunk
        continue
      }
      chunk.frameLength = framesInChunk

      for channel in 0..<Int(channelCount) {
        chunkPointers[channel].update(
          from: channelPointers[channel] + Int(position), count: Int(framesInChunk))
      }

      if let loudness = processAudioChunk(
        chunk, channelCount: channelCount, filterCoefficients: filterCoefficients)
      {
        measurements.append(loudness)
      }

      position += framesInChunk
    }

    return calculateIntegratedLUFS(from: measurements)
  }

  /// True peak (dBTP) of an in-memory buffer, measured the same way as files.
  static func truePeakdBTP(buffer: AVAudioPCMBuffer) -> Float? {
    guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else {
      return nil
    }

    var globalTruePeak: Float = 0
    for channel in 0..<Int(buffer.format.channelCount) {
      var meter = TruePeakMeter()
      meter.process(channelData[channel], count: Int(buffer.frameLength))
      meter.finish()
      globalTruePeak = max(globalTruePeak, meter.peak)
    }

    return globalTruePeak > 0 ? 20 * log10(globalTruePeak) : -Float.infinity
  }

  // MARK: - Duration Analysis

  /// Duration in seconds, or nil if the file can't be read.
  static func getDuration(at url: URL) -> TimeInterval? {
    do {
      let file = try AVAudioFile(forReading: url)
      let frameCount = file.length
      let sampleRate = file.fileFormat.sampleRate
      let duration = Double(frameCount) / sampleRate
      return duration
    } catch {
      Logger.app.error("AudioAnalyzer: Failed to get duration: \(error, privacy: .public)")
      return nil
    }
  }
}
