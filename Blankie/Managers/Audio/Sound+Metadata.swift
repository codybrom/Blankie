//
//  Sound+Metadata.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import AVFoundation
import CoreMedia
import Foundation
import os

// MARK: - Metadata Extraction
extension Sound {
  func extractMetadata(from url: URL) {
    do {
      try extractFileMetadata(from: url)
      extractAudioMetadata(from: url)
    } catch {
      Logger.sounds.error(
        "Sound: Failed to extract metadata for '\(self.fileName, privacy: .public)': \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func extractFileMetadata(from url: URL) throws {
    // Get file attributes
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = attributes[.size] as? Int64
    let format = url.pathExtension.uppercased()

    // Update published properties on main queue to avoid view update warnings
    DispatchQueue.main.async {
      self.fileSize = size
      self.fileFormat = format
    }
  }

  private func extractAudioMetadata(from url: URL) {
    // Create AVURLAsset to extract audio metadata
    let asset = AVURLAsset(url: url)

    // Since deployment target is iOS 26+, we can use async loading directly
    extractAudioMetadataAsync(from: asset)
  }

  private func extractAudioMetadataAsync(from asset: AVURLAsset) {
    Task { @MainActor in
      do {
        // Load duration
        let durationCMTime = try await asset.load(.duration)
        if durationCMTime.isValid && !durationCMTime.isIndefinite {
          self.duration = CMTimeGetSeconds(durationCMTime)
        }

        // Load audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
          let formatDescriptions = try await audioTrack.load(.formatDescriptions)
          extractChannelCount(from: formatDescriptions)
        }

        logMetadata()
      } catch {
        Logger.sounds.error(
          "Sound: Failed to load metadata asynchronously: \(error, privacy: .public)")
      }
    }
  }

  private func extractChannelCount(from formatDescriptions: [CMFormatDescription]) {
    for formatDesc in formatDescriptions {
      if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
        formatDesc)
      {
        channelCount = Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
        break
      }
    }
  }

  private func logMetadata() {
    Logger.sounds.debug(
      "Sound: Metadata for '\(self.fileName)' - Channels: \(self.channelCount ?? 0), Duration: \(self.duration ?? 0)s, Size: \(self.fileSize ?? 0) bytes, Format: \(self.fileFormat ?? "unknown")"
    )
  }
}
