//
//  SpectrumAnalyzer.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import Accelerate

/// Turns a block of audio samples into one level per band, 0...1, for a
/// spectrum display. Levels are relative to the loudest band seen recently, so
/// the tallest bar sits near the top whatever the sound's volume.
///
/// Not thread-safe. Use one instance from one thread (the audio tap).
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
  private static let size = 2048
  private static let log2Size = vDSP_Length(11)
  /// Bands quieter than this many dB below the reference draw as empty.
  private static let displayRangeDB: Float = 30
  /// The loudest band sits this far below the top of the display.
  private static let headroomDB: Float = 4

  private let setup: FFTSetup
  private let edges: [Float]
  private var window = [Float](repeating: 0, count: SpectrumAnalyzer.size)
  private var input = [Float](repeating: 0, count: SpectrumAnalyzer.size)
  private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
  private var imaginary = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
  private var smoothed: [Float]
  private var referenceDB: Float = -120

  /// `centers` are the band center frequencies in Hz, low to high. Each band
  /// runs to the midpoint (on a log scale) between it and its neighbors.
  init(centers: [Float]) {
    setup = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2))!
    vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
    var edges: [Float] = []
    for index in centers.indices {
      let center = centers[index]
      if index == 0 {
        let ratio = centers.count > 1 ? centers[1] / center : 2
        edges.append(center / ratio.squareRoot())
      } else {
        edges.append((centers[index - 1] * center).squareRoot())
      }
    }
    if let last = centers.last {
      let ratio = centers.count > 1 ? last / centers[centers.count - 2] : 2
      edges.append(min(20_000, last * ratio.squareRoot()))
    }
    self.edges = edges
    smoothed = [Float](repeating: 0, count: centers.count)
  }

  deinit {
    vDSP_destroy_fftsetup(setup)
  }

  /// Analyzes the newest samples and returns the smoothed level of each band.
  func process(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) -> [Float] {
    let size = Self.size
    let half = size / 2
    guard !samples.isEmpty, sampleRate > 0 else { return smoothed }

    // Newest `size` samples, zero-padded at the front when the block is short.
    let take = min(size, samples.count)
    for index in 0..<(size - take) { input[index] = 0 }
    for index in 0..<take {
      input[size - take + index] = samples[samples.count - take + index]
    }
    vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(size))

    var power = [Float](repeating: 0, count: half)
    input.withUnsafeBufferPointer { inputPointer in
      real.withUnsafeMutableBufferPointer { realPointer in
        imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
          var split = DSPSplitComplex(
            realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
          inputPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
          }
          vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))
          vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
        }
      }
    }

    // Sum the power in each band, in dB. A full-scale sine comes out near 0 dB.
    let binWidth = sampleRate / Float(size)
    let fullScale = Float(size * size) / 4
    var bandDB = [Float](repeating: -120, count: smoothed.count)
    for band in smoothed.indices {
      let first = max(1, Int((edges[band] / binWidth).rounded(.up)))
      let last = min(half - 1, Int((edges[band + 1] / binWidth).rounded(.down)))
      guard last >= first else { continue }
      var sum: Float = 0
      for bin in first...last { sum += power[bin] }
      bandDB[band] = 10 * log10(sum / fullScale + 1e-12)
    }

    // The reference follows the loudest band up at once. It drifts down slowly,
    // so pulling one band down shows as that bar sinking, not the others rising.
    // When the whole sound drops well below it (a louder start, a fade), it
    // catches up quickly so the display doesn't sit half empty.
    let elapsed = Float(samples.count) / sampleRate
    let loudest = bandDB.max() ?? -120
    let isSilent = loudest < -90
    if !isSilent {
      let fallRate: Float = referenceDB - loudest > 4 ? 12 : 0.2
      referenceDB = max(loudest, referenceDB - fallRate * elapsed)
    }

    let floorDB = referenceDB + Self.headroomDB - Self.displayRangeDB
    for band in smoothed.indices {
      let target =
        isSilent ? 0 : max(0, min(1, (bandDB[band] - floorDB) / Self.displayRangeDB))
      if target > smoothed[band] {
        smoothed[band] += (target - smoothed[band]) * 0.7
      } else {
        smoothed[band] = max(target, smoothed[band] - 1.5 * elapsed)
      }
    }
    return smoothed
  }
}
