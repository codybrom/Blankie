//
//  CustomSoundManager+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

// MARK: - Helper Methods

extension CustomSoundManager {
  func getCustomSoundsDirectoryURL() -> URL? {
    // Use app group container if available, otherwise fall back to documents directory
    if let appGroupURL = AppGroupConfiguration.documentsURL {
      return appGroupURL.appendingPathComponent(customSoundsDirectory)
    } else {
      // Fallback to documents directory
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
      return documentsPath?.appendingPathComponent(customSoundsDirectory)
    }
  }

  func isSupportedAudioFormat(_ extension: String) -> Bool {
    guard let type = UTType(filenameExtension: `extension`) else {
      return false
    }

    return type.conforms(to: .audio)
  }

  /// Extract metadata title from audio file (ID3 tags, etc.)
  func extractMetadataTitle(from url: URL) async -> String? {
    do {
      let asset = AVURLAsset(url: url)

      // Load common metadata which includes ID3 tags
      let metadata = try await asset.load(.commonMetadata)

      // Look for title in metadata
      for item in metadata {
        if let key = item.commonKey, key == .commonKeyTitle {
          if let value = try await item.load(.value) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
              print("🎵 CustomSoundManager: Found metadata title: '\(trimmedValue)'")
              return trimmedValue
            }
          }
        }
      }

      print("ℹ️ CustomSoundManager: No metadata title found in file")
      return nil
    } catch {
      print("⚠️ CustomSoundManager: Failed to extract metadata: \(error)")
      return nil
    }
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
    guard let documentsPath = getCustomSoundsDirectoryURL() else {
      print("❌ CustomSoundManager: Could not get custom sounds directory URL")
      return nil
    }

    let fileName = "\(customSound.fileName).\(customSound.fileExtension)"
    let soundURL = documentsPath.appendingPathComponent(fileName)

    print("🔍 CustomSoundManager: Looking for custom sound file: \(fileName)")
    print("🔍 CustomSoundManager: Expected path: \(soundURL.path)")

    // Verify the file exists
    if FileManager.default.fileExists(atPath: soundURL.path) {
      print("✅ CustomSoundManager: Custom sound file found at: \(soundURL.path)")
      return soundURL
    }

    print("❌ CustomSoundManager: Custom sound file not found at expected path: \(soundURL.path)")

    // Debug: List files in the CustomSounds directory
    do {
      let files = try FileManager.default.contentsOfDirectory(atPath: documentsPath.path)
      print("📂 CustomSoundManager: Files in CustomSounds directory:")
      files.forEach { file in
        print("  - \(file)")
      }
    } catch {
      print("❌ CustomSoundManager: Failed to list files in CustomSounds directory: \(error)")
    }

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
