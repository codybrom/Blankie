//
//  AudioAnalyzer.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate

/// Combined audio analysis results
struct AudioAnalysisResult {
  let lufs: Float?
  let normalizationFactor: Float
  let peakLevel: Float?
  let rmsLevel: Float?
  let truePeakdBTP: Float?
  let needsLimiter: Bool
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

  /// Minimum LUFS to prevent over-amplification of very quiet sounds
  static let minimumLUFS: Float = -50.0

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
        print("❌ AudioAnalyzer: Failed to create buffer")
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

      print("🎵 AudioAnalyzer: Peak level for \(url.lastPathComponent): \(peakLevel)")
      return peakLevel

    } catch {
      print("❌ AudioAnalyzer: Failed to analyze audio file: \(error)")
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

    print(
      "🎵 AudioAnalyzer: Peak normalization factor: \(limitedFactor) (peak: \(peakLevel), target: \(targetLevel))"
    )
    return limitedFactor
  }

  /// Calculate normalization factor based on LUFS measurement
  /// - Parameter lufs: The measured integrated LUFS
  /// - Returns: Linear gain factor to apply
  static func calculateLUFSNormalizationFactor(lufs: Float) -> Float {
    // Don't normalize if already at or above target
    guard lufs < targetLUFS else { return 1.0 }

    // Don't normalize sounds quieter than minimum (too quiet)
    guard lufs > minimumLUFS else { return 1.0 }

    // Calculate required gain in dB
    let requiredGainDB = targetLUFS - lufs

    // Limit the gain
    let limitedGainDB = min(requiredGainDB, maxGainDB)

    // Convert dB to linear gain
    let linearGain = pow(10, limitedGainDB / 20)

    return linearGain
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

      print("🎵 AudioAnalyzer: RMS level for \(url.lastPathComponent): \(averageRMS)")
      return averageRMS

    } catch {
      print("❌ AudioAnalyzer: Failed to analyze RMS: \(error)")
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

        // Process each channel with 4x oversampling
        for channel in 0..<Int(format.channelCount) {
          guard let channelData = buffer.floatChannelData?[channel] else { continue }

          // Simple 4x oversampling using linear interpolation
          let oversampledLength = Int(buffer.frameLength) * 4
          var oversampledData = [Float](repeating: 0, count: oversampledLength)

          // Upsample with linear interpolation
          for i in 0..<Int(buffer.frameLength - 1) {
            let sample1 = channelData[i]
            let sample2 = channelData[i + 1]
            let delta = (sample2 - sample1) / 4.0

            oversampledData[i * 4] = sample1
            oversampledData[i * 4 + 1] = sample1 + delta
            oversampledData[i * 4 + 2] = sample1 + delta * 2
            oversampledData[i * 4 + 3] = sample1 + delta * 3
          }

          // Find peak in oversampled data
          var peak: Float = 0
          vDSP_maxmgv(oversampledData, 1, &peak, vDSP_Length(oversampledLength))
          globalTruePeak = max(globalTruePeak, peak)
        }

        position += AVAudioFramePosition(framesToRead)
      }

      // Convert to dBTP (dB True Peak)
      let truePeakdBTP = globalTruePeak > 0 ? 20 * log10(globalTruePeak) : -Float.infinity
      print("🎵 AudioAnalyzer: True peak for \(url.lastPathComponent): \(truePeakdBTP) dBTP")
      return truePeakdBTP

    } catch {
      print("❌ AudioAnalyzer: Failed to analyze true peak: \(error)")
      return nil
    }
  }

  // MARK: - Comprehensive Analysis

  /// Perform comprehensive audio analysis including LUFS, peak, RMS, and true peak
  /// - Parameter url: URL of the audio file to analyze
  /// - Returns: Complete analysis results
  static func comprehensiveAnalysis(at url: URL) async -> AudioAnalysisResult {
    print("🔍 AudioAnalyzer: Starting comprehensive analysis for \(url.lastPathComponent)")

    // Get peak and RMS levels
    let peakLevel = await analyzePeakLevel(at: url)
    let rmsLevel = await analyzeRMSLevel(at: url)

    // Get true peak level
    let truePeakdBTP = await analyzeTruePeak(at: url)

    // Get LUFS analysis
    let lufsResult = await analyzeLUFS(at: url)

    // Calculate normalization and check if limiter is needed
    let normalizationFactor: Float
    var needsLimiter = false

    if let lufsData = lufsResult {
      normalizationFactor = lufsData.normalizationFactor

      // Check if applying gain would push true peak above -1 dBTP
      if let truePeak = truePeakdBTP {
        let gainDB = targetLUFS - (lufsData.lufs)
        let predictedTruePeak = truePeak + gainDB
        needsLimiter = predictedTruePeak > -1.0

        if needsLimiter {
          print("⚠️ AudioAnalyzer: Limiter needed - predicted peak: \(predictedTruePeak) dBTP")
        }
      }
    } else if let peak = peakLevel {
      // Fallback to peak-based normalization
      normalizationFactor = calculateNormalizationFactor(peakLevel: peak)
      print("⚠️ AudioAnalyzer: Using peak-based normalization as fallback")
    } else {
      normalizationFactor = 1.0
    }

    return AudioAnalysisResult(
      lufs: lufsResult?.lufs,
      normalizationFactor: normalizationFactor,
      peakLevel: peakLevel,
      rmsLevel: rmsLevel,
      truePeakdBTP: truePeakdBTP,
      needsLimiter: needsLimiter
    )
  }

  // MARK: - LUFS Analysis

}
