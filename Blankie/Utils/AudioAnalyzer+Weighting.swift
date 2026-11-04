//
//  AudioAnalyzer+Weighting.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import Accelerate
import os

nonisolated struct KWeightingCoefficients: Sendable {
  let preFilterA: [Float]
  let preFilterB: [Float]
  let rlbFilterA: [Float]
  let rlbFilterB: [Float]
}

extension AudioAnalyzer {

  nonisolated static func getKWeightingCoefficients() -> KWeightingCoefficients {
    // ITU-R BS.1770-4 K-weighting coefficients (a0 is 1.0 for both filters).
    // Pre-filter (high shelf)
    let preFilterB: [Float] = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    let preFilterA: [Float] = [1.0, -1.69065929318241, 0.73248077421585]

    // RLB filter (high-pass)
    let rlbFilterB: [Float] = [1.0, -2.0, 1.0]
    let rlbFilterA: [Float] = [1.0, -1.99004745483398, 0.99007225036621]

    return KWeightingCoefficients(
      preFilterA: preFilterA, preFilterB: preFilterB,
      rlbFilterA: rlbFilterA, rlbFilterB: rlbFilterB)
  }

  nonisolated static func processChannel(
    _ channelData: UnsafeMutablePointer<Float>,
    frameLength: AVAudioFrameCount,
    filterCoefficients: KWeightingCoefficients,
    channelIndex: Int
  ) -> Float {
    var workingData = [Float](repeating: 0, count: Int(frameLength))
    guard kWeight(channelData, into: &workingData, coefficients: filterCoefficients) else {
      Logger.app.error("AudioAnalyzer: Failed to create the K-weighting filter")
      return 0
    }

    var power: Float = 0
    vDSP_measqv(workingData, 1, &power, vDSP_Length(frameLength))

    // Log input vs. filtered power for near-silent channels.
    if power == 0 || power < 1e-10 {
      var inputPower: Float = 0
      vDSP_measqv(
        Array(UnsafeBufferPointer(start: channelData, count: Int(frameLength))), 1, &inputPower,
        vDSP_Length(frameLength))
      Logger.app.debug(
        "AudioAnalyzer: Channel \(channelIndex) - Input power: \(inputPower), Filtered power: \(power)"
      )
    }

    // ITU-R BS.1770 weights surround channels at 1.41.
    let channelWeight: Float = channelIndex < 2 ? 1.0 : 1.41
    return power * channelWeight
  }

  /// Runs the pre-filter and RLB stages as one two-section `vDSP_biquad` cascade. The
  /// delay line starts at zero on every call, so filter state resets per chunk.
  /// Returns false if the filter setup can't be created.
  nonisolated static func kWeight(
    _ input: UnsafePointer<Float>, into output: inout [Float],
    coefficients: KWeightingCoefficients
  ) -> Bool {
    let sections = [
      coefficients.preFilterB[0], coefficients.preFilterB[1], coefficients.preFilterB[2],
      coefficients.preFilterA[1], coefficients.preFilterA[2],
      coefficients.rlbFilterB[0], coefficients.rlbFilterB[1], coefficients.rlbFilterB[2],
      coefficients.rlbFilterA[1], coefficients.rlbFilterA[2],
    ].map(Double.init)
    guard let setup = vDSP_biquad_CreateSetup(sections, 2) else { return false }
    defer { vDSP_biquad_DestroySetup(setup) }

    var delay = [Float](repeating: 0, count: 2 * 2 + 2)
    vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(output.count))
    return true
  }
}
