//
//  AudioAnalyzer+LUFS.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate

extension AudioAnalyzer {

  static func analyzeLUFS(at url: URL) async -> (lufs: Float, normalizationFactor: Float)? {
    do {
      // First run basic audio analysis for debugging
      debugLog("AudioAnalyzer: Starting LUFS analysis for \(url.lastPathComponent)")

      // Get peak and RMS levels for comparison
      if let peakLevel = await analyzePeakLevel(at: url) {
        debugLog("AudioAnalyzer: Peak level: \(peakLevel) (\(20 * log10(peakLevel)) dBFS)")
      }

      if let rmsLevel = await analyzeRMSLevel(at: url) {
        debugLog("AudioAnalyzer: RMS level: \(rmsLevel) (\(20 * log10(rmsLevel)) dBFS)")
      }

      let file = try AVAudioFile(forReading: url)
      let measurements = try await processAudioFileForLUFS(file)
      let integratedLUFS = calculateIntegratedLUFS(from: measurements)

      guard let lufs = integratedLUFS else {
        debugLog("AudioAnalyzer: No measurements above gating threshold")
        return nil
      }

      let normalizationFactor = calculateLUFSNormalizationFactor(lufs: lufs)
      debugLog(
        "AudioAnalyzer: \(url.lastPathComponent) - LUFS: \(lufs), Factor: \(normalizationFactor)")

      return (lufs: lufs, normalizationFactor: normalizationFactor)
    } catch {
      logError("AudioAnalyzer: Failed to analyze LUFS: \(error)")
      return nil
    }
  }

  static func processAudioFileForLUFS(_ file: AVAudioFile) async throws -> [Float] {
    let format = file.processingFormat
    let channelCount = format.channelCount
    let chunkSize: AVAudioFrameCount = 48000
    var measurements: [Float] = []
    var position: AVAudioFramePosition = 0

    debugLog(
      "AudioAnalyzer: Processing file for LUFS - Length: \(file.length) frames, Channels: \(channelCount), Sample Rate: \(format.sampleRate)"
    )

    let filterCoefficients = getKWeightingCoefficients()

    while position < file.length {
      let framesToRead = min(chunkSize, AVAudioFrameCount(file.length - position))

      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
        position += AVAudioFramePosition(framesToRead)
        continue
      }

      file.framePosition = position
      try file.read(into: buffer)

      if let loudness = processAudioChunk(
        buffer, channelCount: channelCount, filterCoefficients: filterCoefficients)
      {
        measurements.append(loudness)
        // Debug: Log the first few measurements
        if measurements.count <= 5 {
          debugLog("AudioAnalyzer: Chunk \(measurements.count) loudness: \(loudness) LUFS")
        }
      }

      position += AVAudioFramePosition(framesToRead)
    }

    return measurements
  }

  static func processAudioChunk(
    _ buffer: AVAudioPCMBuffer,
    channelCount: UInt32,
    filterCoefficients: KWeightingCoefficients
  ) -> Float? {
    var channelPowers: [Float] = []

    for channel in 0..<Int(channelCount) {
      guard let channelData = buffer.floatChannelData?[channel] else { continue }

      let power = processChannel(
        channelData,
        frameLength: buffer.frameLength,
        filterCoefficients: filterCoefficients,
        channelIndex: channel)
      channelPowers.append(power)
    }

    let totalPower = channelPowers.reduce(0, +)
    guard totalPower > 0 else {
      debugLog("AudioAnalyzer: Total power is 0")
      return nil
    }

    let loudness = -0.691 + 10.0 * log10(totalPower)

    // Debug extremely low values
    if loudness < -70 {
      debugLog("AudioAnalyzer: Very low loudness: \(loudness) LUFS (power: \(totalPower))")
    }

    return loudness
  }

  static func calculateIntegratedLUFS(from measurements: [Float]) -> Float? {
    // Debug: Log measurement statistics
    if !measurements.isEmpty {
      let minMeasurement = measurements.min() ?? -999
      let maxMeasurement = measurements.max() ?? -999
      let avgMeasurement = measurements.reduce(0, +) / Float(measurements.count)
      debugLog(
        "AudioAnalyzer: LUFS Measurements - Count: \(measurements.count), Min: \(minMeasurement), Max: \(maxMeasurement), Avg: \(avgMeasurement)"
      )
    }

    // ITU-R BS.1770-4 two-stage gating
    // Stage 1: Absolute threshold at -70 LUFS
    let absoluteGated = measurements.filter { $0 > -70 }
    guard !absoluteGated.isEmpty else {
      debugLog(
        "AudioAnalyzer: All \(measurements.count) measurements below -70 LUFS gating threshold")

      // If all measurements are below -70 LUFS, try without gating for very quiet sounds
      if !measurements.isEmpty {
        let linearMeasurements = measurements.map { pow(10, $0 / 10) }
        let meanLinear = linearMeasurements.reduce(0, +) / Float(linearMeasurements.count)
        let ungatedLUFS = 10 * log10(meanLinear)
        debugLog("AudioAnalyzer: Ungated LUFS would be: \(ungatedLUFS)")

        // For very quiet sounds, we might want to use ungated measurement
        // This is a deviation from the standard but necessary for ambient sounds
        if ungatedLUFS > -100 {
          return ungatedLUFS
        }
      }
      return nil
    }

    // Calculate mean of absolute gated measurements
    let linearMeasurements = absoluteGated.map { pow(10, $0 / 10) }
    let meanLinear = linearMeasurements.reduce(0, +) / Float(linearMeasurements.count)
    let absoluteGatedLUFS = 10 * log10(meanLinear)

    // Stage 2: Relative threshold at -10 LU below the ungated mean
    let relativeThreshold = absoluteGatedLUFS - 10
    let relativeGated = absoluteGated.filter { $0 > relativeThreshold }

    guard !relativeGated.isEmpty else {
      // If relative gating removes all measurements, use absolute gated result
      return absoluteGatedLUFS
    }

    // Calculate final integrated LUFS
    let finalLinearMeasurements = relativeGated.map { pow(10, $0 / 10) }
    let finalMeanLinear =
      finalLinearMeasurements.reduce(0, +) / Float(finalLinearMeasurements.count)

    return 10 * log10(finalMeanLinear)
  }
}
