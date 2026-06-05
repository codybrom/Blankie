//
//  AudioAnalyzer.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate
import os

/// Combined audio analysis results
struct AudioAnalysisResult {
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

/// Utility class for analyzing audio files
class AudioAnalyzer {
  // MARK: - LUFS Configuration

  /// Target LUFS level for normalization
  static let targetLUFS: Float = -27.0

  /// Below this LUFS a sound is left un-normalized (treated as silence/noise).
  /// Kept under the quietest real sound (boat ≈ -49.85) so none sit on the cliff.
  static let minimumLUFS: Float = -60.0

  /// Maximum gain to apply (in dB) to prevent excessive amplification
  static let maxGainDB: Float = 18.0

  /// Analyze an audio file and return its peak level
  /// - Parameter url: URL of the audio file to analyze
  /// - Returns: Peak level (0.0 to 1.0) or nil if analysis fails
  static func analyzePeakLevel(at url: URL) async -> Float? {
    do {
      // Create an audio file for reading
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let frameCount = UInt32(file.length)

      // Read the entire file into a buffer
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        Logger.app.error("AudioAnalyzer: Failed to create buffer")
        return nil
      }

      try file.read(into: buffer)
      buffer.frameLength = frameCount

      // Find the peak level across all channels
      var peakLevel: Float = 0.0

      for channel in 0..<Int(format.channelCount) {
        guard let channelData = buffer.floatChannelData?[channel] else { continue }

        // Use Accelerate framework for efficient peak detection
        var peak: Float = 0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameCount))

        // Also check for negative peaks
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

  /// Calculate normalization factor based on peak level
  /// - Parameters:
  ///   - peakLevel: The detected peak level (0.0 to 1.0)
  ///   - targetLevel: The desired target level (default 0.8 for headroom)
  /// - Returns: Normalization factor to apply
  static func calculateNormalizationFactor(peakLevel: Float, targetLevel: Float = 0.8) -> Float {
    guard peakLevel > 0 else { return 1.0 }

    // Calculate the factor needed to reach target level
    let factor = targetLevel / peakLevel

    // Limit the factor to prevent excessive amplification
    // Max 3x gain (9.5 dB) to avoid amplifying noise in quiet files
    let limitedFactor = min(factor, 3.0)

    Logger.app.debug(
      "AudioAnalyzer: Peak normalization factor: \(limitedFactor) (peak: \(peakLevel), target: \(targetLevel))"
    )
    return limitedFactor
  }

  /// Calculate normalization factor based on LUFS measurement
  /// - Parameter lufs: The measured integrated LUFS
  /// - Returns: Linear gain factor to apply
  static func calculateLUFSNormalizationFactor(lufs: Float) -> Float {
    // Don't touch sounds too quiet to be real signal (avoid amplifying noise/silence)
    guard lufs > minimumLUFS else { return 1.0 }

    // Two-way loudness match toward the target: positive gain boosts quiet
    // sounds, negative gain attenuates loud ones, so built-in and custom sounds
    // land at the same perceived level. Cap only the boost (attenuation is always
    // safe); the soft limiter guards any residual clipping when boosting.
    let requiredGainDB = targetLUFS - lufs
    let limitedGainDB = min(requiredGainDB, maxGainDB)

    return pow(10, limitedGainDB / 20)
  }

  /// Analyze RMS (Root Mean Square) level for more perceptual loudness
  /// - Parameter url: URL of the audio file to analyze
  /// - Returns: RMS level (0.0 to 1.0) or nil if analysis fails
  static func analyzeRMSLevel(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let frameCount = UInt32(file.length)

      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
      }

      try file.read(into: buffer)
      buffer.frameLength = frameCount

      var totalRMS: Float = 0.0
      let channelCount = Int(format.channelCount)

      for channel in 0..<channelCount {
        guard let channelData = buffer.floatChannelData?[channel] else { continue }

        // Calculate RMS for this channel
        var squaredSum: Float = 0
        vDSP_svesq(channelData, 1, &squaredSum, vDSP_Length(frameCount))

        let meanSquare = squaredSum / Float(frameCount)
        let rms = sqrt(meanSquare)

        totalRMS += rms
      }

      // Average RMS across channels
      let averageRMS = totalRMS / Float(channelCount)

      Logger.app.debug("AudioAnalyzer: RMS level for \(url.lastPathComponent): \(averageRMS)")
      return averageRMS

    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze RMS: \(error, privacy: .public)")
      return nil
    }
  }

  // MARK: - True Peak Analysis

  /// Analyze true peak level with 4x oversampling for intersample peak detection
  /// - Parameter url: URL of the audio file to analyze
  /// - Returns: True peak level in dBTP or nil if analysis fails
  static func analyzeTruePeak(at url: URL) async -> Float? {
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let chunkSize: AVAudioFrameCount = 48000
      var globalTruePeak: Float = 0.0
      var position: AVAudioFramePosition = 0

      while position < file.length {
        let framesToRead = min(chunkSize, AVAudioFrameCount(file.length - position))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
          position += AVAudioFramePosition(framesToRead)
          continue
        }

        file.framePosition = position
        try file.read(into: buffer)

        // Process each channel with 4x oversampling (shared with buffer overload)
        for channel in 0..<Int(format.channelCount) {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }
          let peak = oversampledPeak(channelData: channelData, frameLength: buffer.frameLength)
          globalTruePeak = max(globalTruePeak, peak)
        }

        position += AVAudioFramePosition(framesToRead)
      }

      // Convert to dBTP (dB True Peak)
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

  /// Perform comprehensive audio analysis including LUFS, peak, RMS, and true peak
  /// - Parameter url: URL of the audio file to analyze
  /// - Returns: Complete analysis results
  static func comprehensiveAnalysis(at url: URL) async -> AudioAnalysisResult {
    Logger.app.debug("AudioAnalyzer: Starting comprehensive analysis for \(url.lastPathComponent)")

    // Get peak and RMS levels
    let peakLevel = await analyzePeakLevel(at: url)
    let rmsLevel = await analyzeRMSLevel(at: url)

    // Get true peak level
    let truePeakdBTP = await analyzeTruePeak(at: url)

    // Get LUFS analysis
    let lufsResult = await analyzeLUFS(at: url)

    // Get duration
    let duration = getDuration(at: url)

    // Calculate normalization and check if limiter is needed
    let normalizationFactor: Float
    var needsLimiter = false

    if let lufsData = lufsResult {
      normalizationFactor = lufsData.normalizationFactor

      // Check if the gain we actually apply (after caps) would push true peak
      // above -1 dBTP. Attenuated (loud) sounds get a factor < 1, so this stays
      // safe; only boosted sounds can trip the limiter.
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
      // Fallback to peak-based normalization
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
  /// buffer true-peak paths so there is one implementation of the computation.
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

  /// Get the duration of an audio file
  /// - Parameter url: URL of the audio file
  /// - Returns: Duration in seconds, or nil if unable to determine
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
