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

  /// Peak sample magnitude (0 to 1), or nil if the file can't be read.
  @concurrent static func analyzePeakLevel(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      // UInt32(_:) traps on files of 2^32+ frames (~25 h at 48 kHz), and imports have no length cap.
      guard let frameCount = AVAudioFrameCount(exactly: file.length) else { return nil }

      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        Logger.app.error("AudioAnalyzer: Failed to create buffer")
        return nil
      }

      try file.read(into: buffer)
      buffer.frameLength = frameCount

      var peakLevel: Float = 0.0

      for channel in 0..<Int(format.channelCount) {
        guard let channelData = buffer.floatChannelData?[channel] else { continue }

        var peak: Float = 0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameCount))

        var minPeak: Float = 0
        vDSP_minv(channelData, 1, &minPeak, vDSP_Length(frameCount))

        let channelPeak = max(abs(peak), abs(minPeak))
        peakLevel = max(peakLevel, channelPeak)
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
      guard let frameCount = AVAudioFrameCount(exactly: file.length) else { return nil }

      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
      }

      try file.read(into: buffer)
      buffer.frameLength = frameCount

      var totalRMS: Float = 0.0
      let channelCount = Int(format.channelCount)

      for channel in 0..<channelCount {
        guard let channelData = buffer.floatChannelData?[channel] else { continue }

        var squaredSum: Float = 0
        vDSP_svesq(channelData, 1, &squaredSum, vDSP_Length(frameCount))

        let meanSquare = squaredSum / Float(frameCount)
        let rms = sqrt(meanSquare)

        totalRMS += rms
      }

      let averageRMS = totalRMS / Float(channelCount)

      Logger.app.debug("AudioAnalyzer: RMS level for \(url.lastPathComponent): \(averageRMS)")
      return averageRMS

    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze RMS: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - True Peak Analysis

  /// True peak in dBTP, with 4x oversampling to catch intersample peaks.
  @concurrent static func analyzeTruePeak(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let chunkSize: AVAudioFrameCount = 48000
      var globalTruePeak: Float = 0.0
      var position: AVAudioFramePosition = 0

      while position < file.length {
        // Clamp before narrowing, since the remainder alone can exceed UInt32.
        let framesToRead = AVAudioFrameCount(
          min(AVAudioFramePosition(chunkSize), file.length - position))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
          position += AVAudioFramePosition(framesToRead)
          continue
        }

        file.framePosition = position
        try file.read(into: buffer)

        for channel in 0..<Int(format.channelCount) {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }
          let peak = oversampledPeak(channelData: channelData, frameLength: buffer.frameLength)
          globalTruePeak = max(globalTruePeak, peak)
        }

        position += AVAudioFramePosition(framesToRead)
      }

      let truePeakdBTP = globalTruePeak > 0 ? 20 * log10(globalTruePeak) : -Float.infinity
      Logger.app.debug(
        "AudioAnalyzer: True peak for \(url.lastPathComponent): \(truePeakdBTP) dBTP")
      return truePeakdBTP

    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze true peak: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - Comprehensive Analysis

  /// Runs LUFS, peak, RMS, true peak and duration analysis and picks the
  /// normalization factor (LUFS first, peak as the fallback).
  @concurrent static func comprehensiveAnalysis(at url: URL) async -> AudioAnalysisResult {
    Logger.app.debug("AudioAnalyzer: Starting comprehensive analysis for \(url.lastPathComponent)")

    let peakLevel = await analyzePeakLevel(at: url)
    let rmsLevel = await analyzeRMSLevel(at: url)

    let truePeakdBTP = await analyzeTruePeak(at: url)

    let lufsResult = await analyzeLUFS(at: url)

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

  // MARK: - Buffer-Based Analysis

  /// Per-channel 4x linear-oversampled magnitude peak, shared by the URL and
  /// buffer true-peak paths.
  static func oversampledPeak(
    channelData: UnsafeMutablePointer<Float>,
    frameLength: AVAudioFrameCount
  ) -> Float {
    guard frameLength > 1 else {
      var peak: Float = 0
      vDSP_maxmgv(channelData, 1, &peak, vDSP_Length(frameLength))
      return peak
    }

    let oversampledLength = Int(frameLength) * 4
    var oversampledData = [Float](repeating: 0, count: oversampledLength)

    for index in 0..<Int(frameLength - 1) {
      let sample1 = channelData[index]
      let sample2 = channelData[index + 1]
      let delta = (sample2 - sample1) / 4.0

      oversampledData[index * 4] = sample1
      oversampledData[index * 4 + 1] = sample1 + delta
      oversampledData[index * 4 + 2] = sample1 + delta * 2
      oversampledData[index * 4 + 3] = sample1 + delta * 3
    }
    // The loop stops one sample short. Write the final source sample so a
    // peak on the last frame isn't missed.
    oversampledData[(Int(frameLength) - 1) * 4] = channelData[Int(frameLength) - 1]

    var peak: Float = 0
    vDSP_maxmgv(oversampledData, 1, &peak, vDSP_Length(oversampledLength))
    return peak
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

  /// True peak (dBTP) of an in-memory buffer via the shared oversampling helper.
  static func truePeakdBTP(buffer: AVAudioPCMBuffer) -> Float? {
    guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else {
      return nil
    }

    var globalTruePeak: Float = 0
    for channel in 0..<Int(buffer.format.channelCount) {
      let peak = oversampledPeak(
        channelData: channelData[channel], frameLength: buffer.frameLength)
      globalTruePeak = max(globalTruePeak, peak)
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
