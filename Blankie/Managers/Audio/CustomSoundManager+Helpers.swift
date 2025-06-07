//
//  CustomSoundManager+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import AVFoundation
import Foundation

// MARK: - Helper Methods

extension CustomSoundManager {
  func getCustomSoundsDirectoryURL() -> URL? {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    return documentsPath?.appendingPathComponent(customSoundsDirectory)
  }

  func isSupportedAudioFormat(_ extension: String) -> Bool {
    let supportedFormats = ["wav", "mp3", "m4a", "aac", "aiff", "mp4"]
    let lowerExt = `extension`.lowercased()

    // For some files, AAC audio might be in an MP4 container
    if lowerExt == "mp4" {
      // We'll validate it's actually audio in the validation step
      return true
    }

    return supportedFormats.contains(lowerExt)
  }

  func validateAudioFile(at url: URL) async throws -> Result<Void, Error> {
    print("🔍 CustomSoundManager: Validating audio file at \(url.lastPathComponent)")

    // Check file size (max 50MB)
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      if let fileSize = attributes[.size] as? UInt64 {
        let maxSize: UInt64 = 50 * 1024 * 1024  // 50MB
        if fileSize > maxSize {
          print("❌ CustomSoundManager: File too large: \(fileSize) bytes")
          return .failure(CustomSoundError.fileTooLarge)
        }
      }
    } catch {
      print("❌ CustomSoundManager: Failed to get file attributes: \(error)")
      return .failure(CustomSoundError.invalidAudioFile(error))
    }

    // Verify it's a valid audio file and check duration
    do {
      let asset = AVURLAsset(url: url)

      // Check if the file has audio tracks
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      if audioTracks.isEmpty {
        print("❌ CustomSoundManager: No audio tracks found in file")
        return .failure(CustomSoundError.unsupportedFormat)
      }

      // Check duration (max 120 minutes)
      let duration = try await asset.load(.duration)
      let durationInSeconds = CMTimeGetSeconds(duration)

      if durationInSeconds <= 0 || !durationInSeconds.isFinite {
        print("❌ CustomSoundManager: Invalid duration: \(durationInSeconds)")
        return .failure(
          CustomSoundError.invalidAudioFile(
            NSError(
              domain: "CustomSoundManager", code: -1,
              userInfo: [NSLocalizedDescriptionKey: "Invalid audio duration"])))
      }

      let maxDuration: Double = 120 * 60  // 120 minutes
      if durationInSeconds > maxDuration {
        print("❌ CustomSoundManager: Duration too long: \(durationInSeconds) seconds")
        return .failure(CustomSoundError.durationTooLong)
      }

      print("✅ CustomSoundManager: Audio file validated successfully")
      print("   Duration: \(durationInSeconds) seconds")
      print("   Audio tracks: \(audioTracks.count)")

      return .success(())
    } catch {
      print("❌ CustomSoundManager: Failed to load audio asset: \(error)")
      return .failure(CustomSoundError.invalidAudioFile(error))
    }
  }
}

// MARK: - Sound File Management

extension CustomSoundManager {
  /// Get the URL for a custom sound file stored in the app's documents directory
  func getURLForCustomSound(_ customSound: CustomSoundData) -> URL? {
    guard let documentsPath = getCustomSoundsDirectoryURL() else { return nil }

    let fileName = "\(customSound.fileName).\(customSound.fileExtension)"
    let soundURL = documentsPath.appendingPathComponent(fileName)

    // Verify the file exists
    if FileManager.default.fileExists(atPath: soundURL.path) {
      return soundURL
    }

    print("⚠️ CustomSoundManager: Custom sound file not found at expected path: \(soundURL.path)")
    return nil
  }

  /// Returns the file URL for a custom sound data object
  func fileURL(for customSound: CustomSoundData) -> URL? {
    guard let customSoundsDir = getCustomSoundsDirectoryURL() else { return nil }
    let fileName = "\(customSound.fileName).\(customSound.fileExtension)"
    return customSoundsDir.appendingPathComponent(fileName)
  }

  /// Re-analyze the peak level for a custom sound
  func reanalyzePeakLevel(for customSound: CustomSoundData) async -> Float? {
    guard let url = getURLForCustomSound(customSound) else {
      print("❌ CustomSoundManager: Could not get URL for custom sound")
      return nil
    }

    do {
      // Calculate peak level from audio file
      let peakLevel = try await calculatePeakLevel(from: url)

      // Convert to dB
      let peakDB = 20 * log10(max(peakLevel, 0.00001))

      // Update the custom sound record
      customSound.detectedPeakLevel = peakDB

      // Save on main actor
      try await MainActor.run {
        try saveContext()
      }

      print("✅ CustomSoundManager: Re-analyzed peak level: \(peakDB) dB")
      return peakDB

    } catch {
      print("❌ CustomSoundManager: Failed to re-analyze peak level: \(error)")
      return nil
    }
  }

  /// Calculate the peak level from an audio file
  private func calculatePeakLevel(from url: URL) async throws -> Float {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)

    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      print("❌ CustomSoundManager: No audio track found")
      throw CustomSoundError.invalidAudioFile(
        NSError(
          domain: "CustomSoundManager", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "No audio track found"]))
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)
    reader.startReading()

    var peakLevel: Float = 0.0

    while reader.status == .reading {
      if let sampleBuffer = output.copyNextSampleBuffer() {
        peakLevel = max(peakLevel, processSampleBuffer(sampleBuffer))
      }
    }

    return peakLevel
  }

  /// Process a sample buffer and return the peak level found
  private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Float {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      return 0.0
    }

    let length = CMBlockBufferGetDataLength(blockBuffer)
    let sampleBytes = UnsafeMutablePointer<Float>.allocate(
      capacity: length / MemoryLayout<Float>.size)
    defer { sampleBytes.deallocate() }

    CMBlockBufferCopyDataBytes(
      blockBuffer, atOffset: 0, dataLength: length, destination: sampleBytes)

    let sampleCount = length / MemoryLayout<Float>.size
    var peakLevel: Float = 0.0

    for index in 0..<sampleCount {
      let sample = abs(sampleBytes[index])
      if sample > peakLevel {
        peakLevel = sample
      }
    }

    return peakLevel
  }
}

// MARK: - Import Data Structure

struct SoundImportData {
  let sourceURL: URL
  let copiedURL: URL
  let title: String
  let iconName: String
  let uniqueFileName: String
  let fileExtension: String
  let randomizeStartPosition: Bool
}
