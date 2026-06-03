//
//  SoundDetailsSection.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct SoundDetailsSection: View {
  let sound: Sound

  var body: some View {
    Section(header: Text("Details")) {
      // Added date for custom sounds
      if sound.isCustom {
        HStack {
          Text("Added")
          Spacer()
          Text((sound.dateAdded ?? Date()).formatted(date: .abbreviated, time: .omitted))
            .foregroundColor(.secondary)
        }
      }

      // Duration
      if let duration = sound.duration {
        HStack {
          Text("Duration")
          Spacer()
          Text(duration.minuteSecondClock)
            .foregroundColor(.secondary)
        }
      }

      // Channels
      if let channels = sound.channelCount {
        HStack {
          Text("Channels")
          Spacer()
          Text(getChannelsText(from: channels))
            .foregroundColor(.secondary)
        }
      }

      // Format and File Size only for custom sounds
      if sound.isCustom {
        HStack {
          Text("Format")
          Spacer()
          Text(sound.fileExtension.uppercased())
            .foregroundColor(.secondary)
        }

        if let fileSize = sound.fileSize {
          HStack {
            Text("File Size")
            Spacer()
            Text(getFileSizeText(from: fileSize))
              .foregroundColor(.secondary)
          }
        }
      }

      // LUFS
      if let lufs = sound.lufs {
        HStack {
          Text("LUFS")
          Spacer()
          Text(String(format: "%.1f", lufs))
            .foregroundColor(.secondary)
        }
      }

      // Normalization Factor with Gain on same line
      if let normalizationFactor = sound.normalizationFactor {
        let gainDB = 20 * log10(normalizationFactor)
        HStack {
          Text("Normalization Factor")
          Spacer()
          Text(String(format: "%.2fx (%+.1fdB)", normalizationFactor, gainDB))
            .foregroundColor(.secondary)
        }
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
