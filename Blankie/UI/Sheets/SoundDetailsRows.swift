//
//  SoundDetailsRows.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

/// Read-only technical detail rows, shown in Edit Sound's Details disclosure.
struct SoundDetailsRows: View {
  let sound: Sound
  @State private var isReanalyzing = false

  var body: some View {
    Group {
      // Added date for custom sounds
      if sound.isCustom {
        LabeledContent(
          "Added",
          value: (sound.dateAdded ?? Date()).formatted(date: .abbreviated, time: .omitted))
      }

      // Duration
      if let duration = sound.duration {
        LabeledContent("Duration", value: duration.minuteSecondClock)
      }

      // Channels
      if let channels = sound.channelCount {
        LabeledContent("Channels", value: getChannelsText(from: channels))
      }

      // Format and File Size only for custom sounds
      if sound.isCustom {
        LabeledContent("Format", value: sound.fileExtension.uppercased())
      }

      if sound.isCustom, let fileSize = sound.fileSize {
        LabeledContent("File Size", value: getFileSizeText(from: fileSize))
      }

      // LUFS (long-press to force a fresh analysis; deliberately undiscoverable)
      if let lufs = sound.lufs {
        LabeledContent("LUFS") {
          if isReanalyzing {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(String(format: "%.1f", lufs))
          }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.0) {
          guard !isReanalyzing else { return }
          isReanalyzing = true
          Task { @MainActor in
            await sound.reanalyzeAudio()
            isReanalyzing = false
          }
        }
      }

      // Normalization Factor with Gain on same line
      if let normalizationFactor = sound.normalizationFactor {
        let gainDB = 20 * log10(normalizationFactor)
        LabeledContent(
          "Normalization Factor",
          value: String(format: "%.2fx (%+.1fdB)", normalizationFactor, gainDB))
      }
    }
  }

  // MARK: - Helper Methods

  private func getChannelsText(from channels: Int) -> String {
    switch channels {
    case 1:
      return "Mono"
    case 2:
      return "Stereo"
    default:
      return "\(channels) (Multichannel)"
    }
  }

  private func getFileSizeText(from fileSize: Int64) -> String {
    let formatter = ByteCountFormatter()
    return formatter.string(fromByteCount: fileSize)
  }
}
