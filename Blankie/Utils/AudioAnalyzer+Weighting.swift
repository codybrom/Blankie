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
    // ITU-R BS.1770-4 K-weighting filter coefficients
    // Pre-filter (shelving filter)
    let preFilterB: [Float] = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    let preFilterA: [Float] = [1.0, -1.69065929318241, 0.73248077421585]  // a0 should be 1.0

    // RLB filter (high-pass filter)
    let rlbFilterB: [Float] = [1.0, -2.0, 1.0]
    let rlbFilterA: [Float] = [1.0, -1.99004745483398, 0.99007225036621]  // a0 should be 1.0

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
    // Copy input data to avoid modifying the original
    var workingData = Array(UnsafeBufferPointer(start: channelData, count: Int(frameLength)))

    // Apply pre-filter (high shelf) using direct biquad implementation
    workingData = applyBiquadFilter(
      input: workingData,
      filterB: filterCoefficients.preFilterB,
      filterA: filterCoefficients.preFilterA
    )

    // Apply RLB filter (high-pass)
    workingData = applyBiquadFilter(
      input: workingData,
      filterB: filterCoefficients.rlbFilterB,
      filterA: filterCoefficients.rlbFilterA
    )

    // Calculate mean square (power)
    var power: Float = 0
    vDSP_measqv(workingData, 1, &power, vDSP_Length(frameLength))

    // Debug: Check power before and after filtering
    if power == 0 || power < 1e-10 {
      var inputPower: Float = 0
      vDSP_measqv(
        Array(UnsafeBufferPointer(start: channelData, count: Int(frameLength))), 1, &inputPower,
        vDSP_Length(frameLength))
      Logger.app.debug(
        "AudioAnalyzer: Channel \(channelIndex) - Input power: \(inputPower), Filtered power: \(power)"
      )
    }

    // Apply channel weighting (ITU-R BS.1770 specifies different weights for surround channels)
    let channelWeight: Float = channelIndex < 2 ? 1.0 : 1.41
    return power * channelWeight
  }

  nonisolated static func applyBiquadFilter(input: [Float], filterB: [Float], filterA: [Float])
    -> [Float]
  {
    var output = [Float](repeating: 0, count: input.count)

    // State variables for the filter
    var prevInput1: Float = 0
    var prevInput2: Float = 0
    var prevOutput1: Float = 0
    var prevOutput2: Float = 0

    // Extract coefficients (filterA[0] is assumed to be 1.0)
    let coeff0B = filterB[0]
    let coeff1B = filterB[1]
    let coeff2B = filterB[2]
    let coeff1A = filterA[1]
    let coeff2A = filterA[2]

    for index in 0..<input.count {
      let currentInput = input[index]

      // Direct Form II implementation
      // y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
      let currentOutput =
        coeff0B * currentInput + coeff1B * prevInput1 + coeff2B * prevInput2 - coeff1A * prevOutput1
        - coeff2A * prevOutput2

      output[index] = currentOutput

      // Update state variables
      prevInput2 = prevInput1
      prevInput1 = currentInput
      prevOutput2 = prevOutput1
      prevOutput1 = currentOutput
    }

    return output
  }
}
