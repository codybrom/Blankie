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
    Section(
      header: Text(
        String(
          localized: "soundSheet.audioSectionHeader", defaultValue: "Audio",
          comment: "Section header for a sound's audio-processing options."))
    ) {
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
              .foregroundStyle(isPreviewing ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
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

      // Alphabetical, with the two loop-dependent toggles right after Loop.

      // Play/pause fades. Very short clips always hard-cut (a fade would
      // swallow them), regardless of this setting.
      Toggle(isOn: $fadeSound) {
        Text(
          "Fade In and Out"
        )
      }

      Toggle(isOn: $loopSound) {
        Text(
          "Loop Sound"
        )
      }

      // Non-looping one-shots are always preset-only, so the toggle locks on
      // while Loop Sound is off (the stored choice survives re-enabling loop).
      Toggle(isOn: loopSound ? $isPresetUseOnly : .constant(true)) {
        Text(
          "Preset Use Only"
        )
        if loopSound {
          Text("Hides this sound from the Sounds list and All Blankie Sounds.")
        } else {
          Text("Non-looping sounds are always preset use only.")
        }
      }
      .disabled(!loopSound)

      // A random start only makes sense when the loop wraps; on a one-shot it
      // would cut off the beginning, so playback ignores it and the toggle
      // explains itself while disabled.
      Toggle(isOn: $randomizeStartPosition) {
        Text(
          "Randomize Start"
        )
        if !loopSound {
          Text("Only applies when Loop Sound is on.")
        }
      }
      .disabled(!loopSound)

      // Music sounds are mutually exclusive: a preset plays at most one at a
      // time, so starting another music sound stops this one. Built-ins take
      // their music tag from sounds.json, so the toggle is shown but disabled
      // for them — editable only on custom sounds.
      Toggle(isOn: $isMusic) {
        Text("Music")
        if isCustomSound {
          Text("Only one music sound plays at a time. Starting another stops this one.")
        } else {
          Text("Built-in sounds keep their music tag.")
        }
      }
      .disabled(!isCustomSound)

      // Import only: offer (or, for large files, require) re-encoding to AAC to
      // save space. Hidden when there's nothing to gain. Locked on over the
      // size ceiling, since the raw import would otherwise strain memory.
      if mode.isAdd, importConvertForced || importConvertEstimate != nil {
        Toggle(isOn: importConvertForced ? .constant(true) : $convertToAACOnImport) {
          Text("Convert to AAC")
          if importConvertForced {
            Text("Audio files larger than 150 MB must be converted to preserve memory.")
          } else if let estimate = importConvertEstimate {
            Text(
              "Would use about \(estimate.savedFraction.formatted(.percent.precision(.fractionLength(0)))) less space with minimal quality loss."
            )
          }
        }
        .disabled(importConvertForced)
      }

      Toggle(isOn: $normalizeAudio) {
        Text("Sound Check")
        Text(
          "Sound Check adjusts the loudness between different sounds to play at the same volume."
        )
      }

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
