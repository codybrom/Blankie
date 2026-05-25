//
//  SoundSheetForm+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import SwiftUI

// MARK: - Color Helpers
extension CleanSoundSheetForm {
  var textColorForCurrentTheme: Color {
    let color = globalSettings.customAccentColor ?? .accentColor
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }

  func textColorForAccentColor(_ accentColor: AccentColor) -> Color {
    guard let color = accentColor.color else { return .white }
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }
}

// MARK: - Volume Helpers
extension CleanSoundSheetForm {
  var volumePercentageText: String {
    let delta = Double(volumeAdjustment) - 1.0
    return delta.formatted(
      .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
  }
}

// MARK: - Preview Helpers
extension CleanSoundSheetForm {
  func togglePreview() {
    debugLog("🎵 CleanSoundSheetForm: togglePreview called, current isPreviewing: \(isPreviewing)")
    isPreviewing.toggle()
  }

  func startPreview() {
    debugLog("🎵 CleanSoundSheetForm: startPreview called")
    isPreviewing = true
  }

  func stopPreview() {
    debugLog("🎵 CleanSoundSheetForm: stopPreview called")
    isPreviewing = false
  }

  func updatePreviewVolume() {
    debugLog("🎵 CleanSoundSheetForm: updatePreviewVolume called")
    // Volume updates will be handled by onChange modifiers
  }
}

// MARK: - Data Types
extension CleanSoundSheetForm {
  struct NormalizationInfo {
    let lufs: String?
    let peak: String?
    let gain: String
    let factor: String
  }

  struct SoundInfo {
    let channelsText: String
    let durationText: String
    let fileSizeText: String
    let formatText: String
    let creditedAuthor: String?
    let description: String?
  }
}

// MARK: - Normalization Info
extension CleanSoundSheetForm {
  func getNormalizationInfo() -> NormalizationInfo? {
    switch mode {
    case .edit(let sound):
      if sound.isCustom,
        let customSoundDataID = sound.customSoundDataID,
        let customSound = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
      {
        // Custom sound - get detailed info from CustomSoundData
        var lufsStr: String?
        var peakStr: String?
        var normFactor: Float = 1.0

        // Get LUFS if available
        if let lufs = customSound.detectedLUFS {
          lufsStr = String(format: "%.1f LUFS", lufs)
          normFactor =
            customSound.normalizationFactor
            ?? AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: lufs)
        }

        // Get peak level
        if let peakLevel = customSound.detectedPeakLevel {
          let percentage = Int(peakLevel * 100)
          peakStr = "\(percentage)%"
          if normFactor == 1.0 {
            normFactor = AudioAnalyzer.calculateNormalizationFactor(peakLevel: peakLevel)
          }
        }

        let gainDB = 20 * log10(normFactor)
        return NormalizationInfo(
          lufs: lufsStr,
          peak: peakStr,
          gain: String(format: "%+.1fdB", gainDB),
          factor: String(format: "%.2fx", normFactor)
        )
      } else {
        // Built-in sound
        var lufsStr: String?

        if let lufs = sound.lufs {
          lufsStr = String(format: "%.1f LUFS", lufs)
        }

        let normFactor = sound.normalizationFactor ?? 1.0
        let gainDB = 20 * log10(normFactor)

        return NormalizationInfo(
          lufs: lufsStr,
          peak: nil,
          gain: String(format: "%+.1fdB", gainDB),
          factor: String(format: "%.2fx", normFactor)
        )
      }

    case .add:
      return nil
    }
  }
}

// MARK: - Sound Info
extension CleanSoundSheetForm {
  func getSoundInfo() -> SoundInfo? {
    switch mode {
    case .edit(let sound):
      return createSoundInfo(from: sound, includeCredits: !sound.isCustom)

    case .add:
      return nil
    }
  }

  private func createSoundInfo(from sound: Sound, includeCredits: Bool) -> SoundInfo {
    // Ensure metadata is loaded
    if sound.channelCount == nil {
      sound.loadSound()
    }

    let channelsText = getChannelsText(from: sound.channelCount)
    let durationText = getDurationText(from: sound.duration)
    let fileSizeText = getFileSizeText(from: sound.fileSize)
    let formatText = sound.fileFormat ?? "Unknown"

    let creditedAuthor: String?
    let description: String?

    if includeCredits {
      creditedAuthor = SoundCreditsManager.shared.getAuthor(for: sound.originalTitle)
      description = SoundCreditsManager.shared.getDescription(for: sound.originalTitle)
    } else {
      creditedAuthor = nil
      description = nil
    }

    return SoundInfo(
      channelsText: channelsText,
      durationText: durationText,
      fileSizeText: fileSizeText,
      formatText: formatText,
      creditedAuthor: creditedAuthor,
      description: description
    )
  }

  private func getChannelsText(from channels: Int?) -> String {
    guard let channels = channels else { return "Unknown" }

    switch channels {
    case 1:
      return "Mono"
    case 2:
      return "Stereo"
    default:
      return "\(channels) (Multichannel)"
    }
  }

  private func getDurationText(from duration: TimeInterval?) -> String {
    guard let duration = duration else { return "Unknown" }

    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  private func getFileSizeText(from fileSize: Int64?) -> String {
    guard let fileSize = fileSize else { return "Unknown" }

    let formatter = ByteCountFormatter()
    return formatter.string(fromByteCount: fileSize)
  }
}
