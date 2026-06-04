//
//  SoundSheetAudioProcessing.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

extension SoundSheetForm {
  @ViewBuilder
  var audioProcessingSection: some View {
    Section(header: Text("Audio")) {
      // Preview with waveform
      HStack(spacing: 12) {
        // Play/Stop button
        Button(action: {
          togglePreview()
        }) {
          ZStack {
            Circle()
              .fill(isPreviewing ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
              .frame(width: 44, height: 44)
              .accessibilityHidden(true)

            Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
              .font(.system(size: 18, weight: .medium))
              .foregroundColor(
                isPreviewing ? .red : (globalSettings.customAccentColor ?? .accentColor)
              )
              .contentTransition(
                .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPreviewing ? Text("Stop Preview") : Text("Play Preview"))
        .disabled(isDisappearing)
        .scaleEffect(isPreviewing ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPreviewing)

        // Waveform
        if let fileURL = selectedFile {
          // For add mode with selected file
          SoundWaveformView(
            sound: nil,
            fileURL: fileURL,
            progress: $previewProgress,
            isPlaying: isPreviewing
          )
          .accessibilityHidden(true)
        } else if case .edit(let sound) = mode {
          if sound.isCustom,
            let customSoundDataID = sound.customSoundDataID,
            let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID),
            let fileURL = CustomSoundManager.shared.fileURL(for: customSoundData)
          {
            // Custom sound - use file URL
            SoundWaveformView(
              sound: nil,
              fileURL: fileURL,
              progress: $previewProgress,
              isPlaying: isPreviewing
            )
            .accessibilityHidden(true)
          } else {
            // Built-in sound - use sound directly
            SoundWaveformView(
              sound: sound,
              fileURL: nil,
              progress: $previewProgress,
              isPlaying: isPreviewing
            )
            .accessibilityHidden(true)
          }
        }
      }
      .frame(height: 44)
      .padding(.vertical, 4)

      Toggle(isOn: $randomizeStartPosition) {
        Text(
          "Randomize Start Position"
        )
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)

      Toggle(isOn: $loopSound) {
        Text(
          "Loop Sound"
        )
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)

      Toggle(isOn: $normalizeAudio) {
        Text("Sound Check")
        Text(
          "Sound Check adjusts the loudness between different sounds to play at the same volume."
        )
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)

      // Volume Adjustment (only visible when normalization is OFF)
      if !normalizeAudio {
        volumeAdjustmentView
      }
    }
  }

  @ViewBuilder
  var technicalDetailsSection: some View {
    if case .edit(let sound) = mode {
      Section(header: Text("Technical Details")) {
        SoundDetailsRows(sound: sound)
      }
    }
  }

  @ViewBuilder
  var volumeAdjustmentView: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Volume Adjustment")
        Spacer()
        Text(volumePercentageText)
          .font(.caption)
          .foregroundColor(.secondary)
          .accessibilityHidden(true)
      }

      HStack {
        Text(
          (-0.5).formatted(
            .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .accessibilityHidden(true)

        Slider(value: $volumeAdjustment, in: 0.5...8.0, step: 0.01)
          .tint(globalSettings.customAccentColor ?? .accentColor)
          .accessibilityLabel(Text("Volume Adjustment"))
          .accessibilityValue(Text(volumePercentageText))

        Text(
          (7.0).formatted(
            .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .accessibilityHidden(true)
      }
    }
  }
}
