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
  @State private var compressionEstimate: CustomSoundManager.CompressionEstimate?
  @State private var showCompressionOffer = false
  @State private var showAlreadyOptimized = false
  @State private var isConverting = false
  @State private var conversionError: String?
  @State private var showConversionError = false

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

      // Format and File Size only for custom sounds. Long-press either to be
      // offered AAC conversion when the file is worth shrinking (see offerCompression).
      if sound.isCustom {
        LabeledContent("Format", value: sound.fileExtension.uppercased())
          .contentShape(Rectangle())
          .onLongPressGesture(minimumDuration: 0.5) { offerCompression() }
      }

      if sound.isCustom, let fileSize = sound.fileSize {
        LabeledContent("File Size") {
          if isConverting {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(getFileSizeText(from: fileSize))
          }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { offerCompression() }
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
    .alert(
      "Convert to AAC?", isPresented: $showCompressionOffer, presenting: compressionEstimate
    ) { _ in
      Button("Convert") { convertToAAC() }
      Button("Cancel", role: .cancel) {}
    } message: { estimate in
      Text(compressionMessage(for: estimate))
    }
    .alert("Already optimized", isPresented: $showAlreadyOptimized) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("This sound is already saved efficiently. Converting wouldn't free up much space.")
    }
    .alert(
      "Couldn't convert", isPresented: $showConversionError, presenting: conversionError
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(message)
    }
  }

  // MARK: - AAC Conversion

  /// Long-press handler for the Format / File Size rows. Offers conversion when
  /// the file is worth shrinking, otherwise tells the user it's already efficient.
  private func offerCompression() {
    guard sound.isCustom, !isConverting else { return }
    if let estimate = CustomSoundManager.shared.compressionEstimate(
      forExtension: sound.fileExtension, currentBytes: sound.fileSize, duration: sound.duration)
    {
      compressionEstimate = estimate
      showCompressionOffer = true
    } else {
      showAlreadyOptimized = true
    }
  }

  private func convertToAAC() {
    guard let id = sound.customSoundDataID, !isConverting else { return }
    isConverting = true
    Task { @MainActor in
      let result = await CustomSoundManager.shared.convertToAAC(soundDataID: id)
      isConverting = false
      switch result {
      case .success:
        // The sound is refreshed in place, so the editor stays open and its
        // Format / File Size rows update to the new values.
        break
      case .failure(let error):
        conversionError = error.localizedDescription
        showConversionError = true
      }
    }
  }

  private func compressionMessage(for estimate: CustomSoundManager.CompressionEstimate) -> String {
    // Formatted as a String (not a literal %) so it localizes and avoids a
    // printf-style % pitfall in the localized format.
    let savings = estimate.savedFraction.formatted(.percent.precision(.fractionLength(0)))
    return String(
      localized:
        "Converting to AAC would use about \(savings) less space, with minimal quality loss. This replaces the original and can't be undone."
    )
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
