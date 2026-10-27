//
//  CustomSoundManager+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers
import os

// MARK: - Helper Methods

extension CustomSoundManager {
  /// Deletes an import source only if it's in the app's transient staging (`tmp` or
  /// `Documents/Inbox`): a file-picker copy or an open-in drop. The user's own files
  /// are never touched. Complements the launch-time staging sweep.
  func removeStagedImportSource(_ url: URL) {
    let path = url.standardizedFileURL.path
    var roots = [URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path]
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      roots.append(docs.appendingPathComponent("Inbox").standardizedFileURL.path)
    }
    guard roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
    do {
      try FileManager.default.removeItem(at: url)
      Logger.sounds.debug(
        "CustomSoundManager: removed staged import source \(url.lastPathComponent, privacy: .public)"
      )
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: couldn't remove staged import source: \(error, privacy: .public)")
    }
  }

  func getCustomSoundsDirectoryURL() -> URL? {
    if let appGroupURL = AppGroupConfiguration.documentsURL {
      return appGroupURL.appendingPathComponent(customSoundsDirectory)
    } else {
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

  /// The file's metadata title (ID3 and similar tags), if any.
  func extractMetadataTitle(from url: URL) async -> String? {
    do {
      let asset = AVURLAsset(url: url)

      let metadata = try await asset.load(.commonMetadata)

      for item in metadata {
        if let key = item.commonKey, key == .commonKeyTitle {
          if let value = try await item.load(.value) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
              Logger.sounds.debug("CustomSoundManager: Found metadata title: '\(trimmedValue)'")
              return trimmedValue
            }
          }
        }
      }

      Logger.sounds.debug("ℹ️ CustomSoundManager: No metadata title found in file")
      return nil
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to extract metadata: \(error, privacy: .public)")
      return nil
    }
  }

  func validateAudioFile(at url: URL) async throws -> Result<Void, Error> {
    Logger.sounds.debug("CustomSoundManager: Validating audio file at \(url.lastPathComponent)")

    // No size cap: oversized files are transcoded to AAC on import (see importSound).
    do {
      let asset = AVURLAsset(url: url)

      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      if audioTracks.isEmpty {
        Logger.sounds.debug("CustomSoundManager: No audio tracks found in file")
        return .failure(CustomSoundError.unsupportedFormat)
      }

      // Validate the duration is a real, positive length (no upper cap).
      let duration = try await asset.load(.duration)
      let durationInSeconds = CMTimeGetSeconds(duration)

      if durationInSeconds <= 0 || !durationInSeconds.isFinite {
        Logger.sounds.error(
          "CustomSoundManager: Invalid duration: \(durationInSeconds, privacy: .public)")
        return .failure(
          CustomSoundError.invalidAudioFile(
            NSError(
              domain: "CustomSoundManager", code: -1,
              userInfo: [NSLocalizedDescriptionKey: "Invalid audio duration"])))
      }

      Logger.sounds.debug("CustomSoundManager: Audio file validated successfully")
      Logger.sounds.debug("   Duration: \(durationInSeconds) seconds")
      Logger.sounds.debug("   Audio tracks: \(audioTracks.count)")

      return .success(())
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to load audio asset: \(error, privacy: .public)")
      return .failure(CustomSoundError.invalidAudioFile(error))
    }
  }
}

// MARK: - Sound File Management

extension CustomSoundManager {
  /// The custom sound's file URL, or nil when the file is missing.
  func getURLForCustomSound(_ customSound: CustomSoundData) -> URL? {
    guard let documentsPath = getCustomSoundsDirectoryURL() else {
      Logger.sounds.error("CustomSoundManager: Could not get custom sounds directory URL")
      return nil
    }

    let fileName = "\(customSound.fileName).\(customSound.fileExtension)"
    let soundURL = documentsPath.appendingPathComponent(fileName)

    if FileManager.default.fileExists(atPath: soundURL.path) {
      return soundURL
    }

    Logger.sounds.debug(
      "CustomSoundManager: Custom sound file not found: \(fileName) at \(soundURL.path)")

    do {
      let files = try FileManager.default.contentsOfDirectory(atPath: documentsPath.path)
      Logger.sounds.debug("CustomSoundManager: Files in CustomSounds directory:")
      for file in files {
        Logger.sounds.debug("  - \(file)")
      }
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to list files in CustomSounds directory: \(error, privacy: .public)"
      )
    }

    return nil
  }

  /// File names (no extension) of the custom audio files on disk. Launch pruning
  /// counts these as valid so a row lost to a store rebuild can't strip a
  /// reference whose audio still exists.
  func customAudioFileNamesOnDisk() -> Set<String> {
    guard let dir = getCustomSoundsDirectoryURL(),
      let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
    else { return [] }
    return Set(
      entries
        .filter { !$0.hasPrefix(".") && !$0.hasSuffix(Self.mirrorSuffix) }
        .map { ($0 as NSString).deletingPathExtension })
  }

  /// The expected file URL, whether or not the file exists.
  func fileURL(for customSound: CustomSoundData) -> URL? {
    guard let customSoundsDir = getCustomSoundsDirectoryURL() else { return nil }
    let fileName = "\(customSound.fileName).\(customSound.fileExtension)"
    return customSoundsDir.appendingPathComponent(fileName)
  }

  /// Re-measures and saves a custom sound's peak level in dB.
  func reanalyzePeakLevel(for customSound: CustomSoundData) async -> Float? {
    guard let url = getURLForCustomSound(customSound) else {
      Logger.sounds.error("CustomSoundManager: Could not get URL for custom sound")
      return nil
    }

    do {
      let peakLevel = try await calculatePeakLevel(from: url)

      let peakDB = 20 * log10(max(peakLevel, 0.00001))

      customSound.detectedPeakLevel = peakDB

      try await MainActor.run {
        try saveContext()
      }

      Logger.sounds.debug("CustomSoundManager: Re-analyzed peak level: \(peakDB) dB")
      return peakDB

    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to re-analyze peak level: \(error, privacy: .public)")
      return nil
    }
  }

  private func calculatePeakLevel(from url: URL) async throws -> Float {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)

    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      Logger.sounds.debug("CustomSoundManager: No audio track found")
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
