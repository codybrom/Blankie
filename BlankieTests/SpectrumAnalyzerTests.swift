//
//  SpectrumAnalyzerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 11/24/26.
//
//  The equalizer's spectrum display: a tone lights the band it sits in and silence lights none.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct SpectrumAnalyzerTests {
  private static let sampleRate: Float = 48_000

  /// Feeds enough blocks of a sine for the smoothed levels to settle.
  private func levels(forToneAt frequency: Float) -> [Float] {
    let analyzer = SpectrumAnalyzer(centers: SoundEqualizer.frequencies)
    var levels: [Float] = []
    var phase: Float = 0
    let step = 2 * Float.pi * frequency / Self.sampleRate
    for _ in 0..<12 {
      var block = [Float](repeating: 0, count: 4_096)
      for index in block.indices {
        block[index] = 0.5 * sin(phase)
        phase += step
      }
      levels = block.withUnsafeBufferPointer {
        analyzer.process($0, sampleRate: Self.sampleRate)
      }
    }
    return levels
  }

  @Test(arguments: Array(SoundEqualizer.frequencies.enumerated()))
  func toneLightsItsOwnBandMost(band: Int, frequency: Float) {
    let levels = levels(forToneAt: frequency)
    #expect(levels.count == SoundEqualizer.frequencies.count)
    #expect(levels.firstIndex(of: levels.max() ?? 0) == band)
    #expect(levels[band] > 0.7)
  }

  @Test func silenceLightsNothing() {
    let analyzer = SpectrumAnalyzer(centers: SoundEqualizer.frequencies)
    let block = [Float](repeating: 0, count: 4_096)
    var levels: [Float] = []
    for _ in 0..<4 {
      levels = block.withUnsafeBufferPointer {
        analyzer.process($0, sampleRate: Self.sampleRate)
      }
    }
    #expect(levels.allSatisfy { $0 == 0 })
  }

  @Test func emptyBlockKeepsTheLastLevels() {
    let analyzer = SpectrumAnalyzer(centers: SoundEqualizer.frequencies)
    let empty = UnsafeBufferPointer<Float>(start: nil, count: 0)
    #expect(analyzer.process(empty, sampleRate: Self.sampleRate) == [0, 0, 0, 0, 0, 0, 0])
  }
}
