//
//  SoundSpectrumMeter.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import AVFoundation
import SwiftUI

/// SPIKE: live band levels for one sound, read after its EQ so the display shows
/// what is being heard. Taps the sound's EQ node while started and follows the
/// sound if its player is rebuilt. Spatial sounds skip that node, so they show
/// nothing.
@MainActor
@Observable
final class SoundSpectrumMeter {
  /// One level per band, 0...1.
  private(set) var levels: [Float]

  @ObservationIgnored private let centers: [Float]
  @ObservationIgnored private weak var tappedNode: AVAudioNode?
  @ObservationIgnored private var watcher: Task<Void, Never>?

  init(centers: [Float]) {
    self.centers = centers
    levels = [Float](repeating: 0, count: centers.count)
  }

  func start(for sound: Sound) {
    watcher?.cancel()
    watcher = Task { [weak self] in
      while !Task.isCancelled {
        self?.refresh(for: sound)
        try? await Task.sleep(for: .milliseconds(300))
      }
    }
  }

  func stop() {
    watcher?.cancel()
    watcher = nil
    tappedNode?.removeTap(onBus: 0)
    tappedNode = nil
    clear()
  }

  private func refresh(for sound: Sound) {
    let eq = (sound.player as? SoundPlayer)?.gain
    let node: AVAudioNode? = eq?.engine != nil ? eq : nil
    if node !== tappedNode {
      tappedNode?.removeTap(onBus: 0)
      tappedNode = node
      node?.installTap(
        onBus: 0, bufferSize: 2048, format: nil,
        block: Self.tapBlock(analyzer: SpectrumAnalyzer(centers: centers), meter: self))
    }
    // The tap goes quiet when the engine idles, so empty the display by hand.
    if !sound.isPlaying { clear() }
  }

  private func clear() {
    guard levels.contains(where: { $0 > 0 }) else { return }
    levels = [Float](repeating: 0, count: centers.count)
  }

  fileprivate func show(_ newLevels: [Float]) {
    guard tappedNode != nil else { return }
    levels = newLevels
  }

  /// Built off the main actor: the tap calls this block on an audio thread.
  nonisolated private static func tapBlock(
    analyzer: SpectrumAnalyzer, meter: SoundSpectrumMeter
  ) -> AVAudioNodeTapBlock {
    { [weak meter] buffer, _ in
      guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
      let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
      let levels = analyzer.process(samples, sampleRate: Float(buffer.format.sampleRate))
      Task { @MainActor in
        meter?.show(levels)
      }
    }
  }
}

/// SPIKE: one LED-style column for one band, like the display on an old hi-fi.
/// Doubles as the track for a band's fader. Hidden from VoiceOver on its own.
struct SpectrumColumn: View {
  let level: Float
  var height: CGFloat = 200

  private static let segmentHeight: CGFloat = 5
  private static let spacing: CGFloat = 3

  var body: some View {
    let segments = Int((height + Self.spacing) / (Self.segmentHeight + Self.spacing))
    let lit = Int((level * Float(segments)).rounded())
    VStack(spacing: Self.spacing) {
      ForEach((0..<segments).reversed(), id: \.self) { segment in
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(.tint)
          .opacity(segment < lit ? (segment == lit - 1 ? 0.9 : 0.45) : 0.1)
          .frame(width: 28, height: Self.segmentHeight)
      }
    }
    .frame(height: height)
    .animation(.linear(duration: 0.1), value: lit)
    .accessibilityHidden(true)
  }
}
