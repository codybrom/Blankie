//
//  SoundWaveformView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/10/25.
//

import AVFoundation
import SwiftUI

struct SoundWaveformView: View {
  let sound: Sound?
  let fileURL: URL?
  @Binding var progress: Double
  let isPlaying: Bool

  @State private var waveformSamples: [Float] = []
  @State private var isLoading = false
  @ObservedObject private var globalSettings = GlobalSettings.shared

  private let barWidth: CGFloat = 2
  private let barSpacing: CGFloat = 2
  private let height: CGFloat = 40

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if isLoading {
          // Loading state
          HStack(spacing: barSpacing) {
            ForEach(0..<20, id: \.self) { index in
              RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: barWidth, height: height * 0.3)
                .scaleEffect(y: isLoading ? 1.0 : 0.5)
                .animation(
                  .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.08),
                  value: isLoading
                )
            }
          }
          .frame(height: height)
        } else if !waveformSamples.isEmpty {
          // Waveform display
          HStack(spacing: barSpacing) {
            ForEach(Array(waveformSamples.enumerated()), id: \.offset) { index, sample in
              WaveformBar(
                height: CGFloat(sample) * height,
                progress: progress,
                index: index,
                totalBars: waveformSamples.count,
                isPlaying: isPlaying,
                accentColor: globalSettings.customAccentColor ?? .accentColor
              )
            }
          }
          .frame(height: height)
        } else {
          // Empty state
          Text("No waveform data")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(height: height)
        }
      }
      .frame(width: geometry.size.width, height: height)
      .onAppear {
        loadWaveform(width: geometry.size.width)
      }
      .onChange(of: geometry.size.width) { _, newWidth in
        loadWaveform(width: newWidth)
      }
    }
    .frame(height: height)
  }

  private func loadWaveform(width: CGFloat) {
    guard let url = getAudioURL(), !isLoading else { return }

    isLoading = true

    Task.detached(priority: .userInitiated) {
      do {
        let samples = try await extractAndDownsampleAudio(from: url, targetWidth: width)
        await MainActor.run {
          self.waveformSamples = samples
          self.isLoading = false
        }
      } catch {
        debugLog("Failed to load waveform: \(error)")
        await MainActor.run {
          self.isLoading = false
        }
      }
    }
  }

  private func getAudioURL() -> URL? {
    if let fileURL = fileURL {
      return fileURL
    } else if let sound = sound {
      return sound.fileURL
        ?? Bundle.main.url(forResource: sound.fileName, withExtension: sound.fileExtension)
    }
    return nil
  }

  private func extractAndDownsampleAudio(from url: URL, targetWidth: CGFloat) async throws
    -> [Float]
  {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = UInt32(file.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return []
    }

    try file.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
      return []
    }

    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))

    // Calculate number of bars that can fit
    let barCount = Int((targetWidth + barSpacing) / (barWidth + barSpacing))

    // Downsample to target number of bars
    return downsample(samples, to: barCount)
  }

  private func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
    guard samples.count > targetCount else {
      return samples.map { abs($0) }
    }

    let chunkSize = samples.count / targetCount
    var downsampled: [Float] = []

    for index in 0..<targetCount {
      let start = index * chunkSize
      let end = min((index + 1) * chunkSize, samples.count)
      let chunk = samples[start..<end]

      // Use RMS (Root Mean Square) for better visual representation
      let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
      downsampled.append(min(rms * 3, 1.0))  // Scale and clamp
    }

    return downsampled
  }
}

struct WaveformBar: View {
  let height: CGFloat
  let progress: Double
  let index: Int
  let totalBars: Int
  let isPlaying: Bool
  let accentColor: Color

  private var isActive: Bool {
    let barProgress = Double(index) / Double(totalBars)
    return barProgress <= progress
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(isActive ? accentColor : Color.secondary.opacity(0.3))
      .frame(width: 2, height: max(2, height))
      .scaleEffect(y: isPlaying && isActive ? 1.1 : 1.0)
      .animation(.easeInOut(duration: 0.2), value: isActive)
      .animation(.easeInOut(duration: 0.3), value: isPlaying)
  }
}

#if DEBUG
  struct SoundWaveformView_Previews: PreviewProvider {
    static var previews: some View {
      VStack {
        SoundWaveformView(
          sound: nil,
          fileURL: nil,
          progress: .constant(0.5),
          isPlaying: true
        )
        .padding()
      }
    }
  }
#endif
