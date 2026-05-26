//
//  SoundSheetSoundInfo.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

extension CleanSoundSheetForm {
  @ViewBuilder
  var soundInformationSection: some View {
    if let soundInfo = getSoundInfo() {
      Section(header: Text("Sound Information")) {
        // Channels
        HStack {
          Text("Channels")
          Spacer()
          Text(soundInfo.channelsText)
            .foregroundColor(.secondary)
        }

        // Duration
        HStack {
          Text("Duration")
          Spacer()
          Text(soundInfo.durationText)
            .foregroundColor(.secondary)
        }

        // File Size
        HStack {
          Text("File Size")
          Spacer()
          Text(soundInfo.fileSizeText)
            .foregroundColor(.secondary)
        }

        // File Format
        HStack {
          Text("Format")
          Spacer()
          Text(soundInfo.formatText)
            .foregroundColor(.secondary)
        }

        // Normalization Data (if available)
        if let normInfo = getNormalizationInfo() {
          normalizationInfoRows(normInfo)
        }

        // Credited Author (if available)
        if let author = soundInfo.creditedAuthor {
          HStack {
            Text("Author")
            Spacer()
            Text(author)
              .foregroundColor(.secondary)
          }
        }

        // Description (if available)
        if let description = soundInfo.description {
          VStack(alignment: .leading, spacing: 4) {
            Text("Description")
            Text(description)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  func normalizationInfoRows(_ normInfo: NormalizationInfo) -> some View {
    // LUFS (if available)
    if let lufs = normInfo.lufs {
      HStack {
        Text("Loudness (LUFS)")
        Spacer()
        Text(lufs)
          .foregroundColor(.secondary)
      }
    }

    // Peak Level (if available)
    if let peak = normInfo.peak {
      HStack {
        Text("Peak Level")
        Spacer()
        Text(peak)
          .foregroundColor(.secondary)
      }
    }

    // Normalization Factor
    HStack {
      Text("Normalization Factor")
      Spacer()
      Text(normInfo.factor)
        .foregroundColor(.secondary)
    }

    // Normalization Gain in dB
    HStack {
      Text("Normalization Gain")
      Spacer()
      Text(normInfo.gain)
        .foregroundColor(.secondary)
    }
  }
}
