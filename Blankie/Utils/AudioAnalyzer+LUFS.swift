//
//  AudioAnalyzer+LUFS.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate
import os

extension AudioAnalyzer {

  @concurrent static func analyzeLUFS(at url: URL) async -> (
    lufs: Float, normalizationFactor: Float
  )? {
    do {
      Logger.app.debug("AudioAnalyzer: Starting LUFS analysis for \(url.lastPathComponent)")

      // Peak and RMS are logged for comparison only.
      if let peakLevel = await analyzePeakLevel(at: url) {
        Logger.app.debug("AudioAnalyzer: Peak level: \(peakLevel) (\(20 * log10(peakLevel)) dBFS)")
      }

      if let rmsLevel = await analyzeRMSLevel(at: url) {
        Logger.app.debug("AudioAnalyzer: RMS level: \(rmsLevel) (\(20 * log10(rmsLevel)) dBFS)")
      }

      let file = try AVAudioFile(forReading: url)
      let measurements = try await processAudioFileForLUFS(file)
      let integratedLUFS = calculateIntegratedLUFS(from: measurements)

      guard let lufs = integratedLUFS else {
        Logger.app.debug("AudioAnalyzer: No measurements above gating threshold")
        return nil
      }

      let normalizationFactor = calculateLUFSNormalizationFactor(lufs: lufs)
      Logger.app.debug(
        "AudioAnalyzer: \(url.lastPathComponent) - LUFS: \(lufs), Factor: \(normalizationFactor)")

      return (lufs: lufs, normalizationFactor: normalizationFactor)
    } catch {
      Logger.app.error("AudioAnalyzer: Failed to analyze LUFS: \(error, privacy: .public)")
      return nil
    }
  }

  nonisolated static func processAudioFileForLUFS(_ file: AVAudioFile) async throws -> [Float] {
    let format = file.processingFormat
    let channelCount = format.channelCount
    let chunkSize: AVAudioFrameCount = 48000
    var measurements: [Float] = []
    var position: AVAudioFramePosition = 0

    Logger.app.debug(
      "AudioAnalyzer: Processing file for LUFS - Length: \(file.length) frames, Channels: \(channelCount), Sample Rate: \(format.sampleRate)"
    )

    let filterCoefficients = getKWeightingCoefficients()

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

      if let loudness = processAudioChunk(
        buffer, channelCount: channelCount, filterCoefficients: filterCoefficients)
      {
        measurements.append(loudness)
        if measurements.count <= 5 {
          Logger.app.debug("AudioAnalyzer: Chunk \(measurements.count) loudness: \(loudness) LUFS")
        }
      }

      position += AVAudioFramePosition(framesToRead)
    }

    return measurements
  }

  nonisolated static func processAudioChunk(
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
      Logger.app.debug("AudioAnalyzer: Total power is 0")
      return nil
    }

    let loudness = -0.691 + 10.0 * log10(totalPower)

    if loudness < -70 {
      Logger.app.debug("AudioAnalyzer: Very low loudness: \(loudness) LUFS (power: \(totalPower))")
    }

    return loudness
  }

  nonisolated static func calculateIntegratedLUFS(from measurements: [Float]) -> Float? {
    if !measurements.isEmpty {
      let minMeasurement = measurements.min() ?? -999
      let maxMeasurement = measurements.max() ?? -999
      let avgMeasurement = measurements.reduce(0, +) / Float(measurements.count)
      Logger.app.debug(
        "AudioAnalyzer: LUFS Measurements - Count: \(measurements.count), Min: \(minMeasurement), Max: \(maxMeasurement), Avg: \(avgMeasurement)"
      )
    }

    // ITU-R BS.1770-4 two-stage gating
    // Stage 1: absolute threshold at -70 LUFS.
    let absoluteGated = measurements.filter { $0 > -70 }
    guard !absoluteGated.isEmpty else {
      Logger.app.debug(
        "AudioAnalyzer: All \(measurements.count) measurements below -70 LUFS gating threshold")

      // Ambient sounds can sit entirely below the gate, so fall back to the
      // ungated mean (a deliberate deviation from BS.1770).
      if !measurements.isEmpty {
        let linearMeasurements = measurements.map { pow(10, $0 / 10) }
        let meanLinear = linearMeasurements.reduce(0, +) / Float(linearMeasurements.count)
        let ungatedLUFS = 10 * log10(meanLinear)
        Logger.app.debug("AudioAnalyzer: Ungated LUFS would be: \(ungatedLUFS)")

        if ungatedLUFS > -100 {
          return ungatedLUFS
        }
      }
      return nil
    }

    let linearMeasurements = absoluteGated.map { pow(10, $0 / 10) }
    let meanLinear = linearMeasurements.reduce(0, +) / Float(linearMeasurements.count)
    let absoluteGatedLUFS = 10 * log10(meanLinear)

    // Stage 2: relative threshold 10 LU below the absolute-gated mean.
    let relativeThreshold = absoluteGatedLUFS - 10
    let relativeGated = absoluteGated.filter { $0 > relativeThreshold }

    guard !relativeGated.isEmpty else {
      return absoluteGatedLUFS
    }

    let finalLinearMeasurements = relativeGated.map { pow(10, $0 / 10) }
    let finalMeanLinear =
      finalLinearMeasurements.reduce(0, +) / Float(finalLinearMeasurements.count)

    return 10 * log10(finalMeanLinear)
  }
}
