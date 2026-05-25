//
//  Sound+Metadata.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Metadata Extraction
extension Sound {
  func extractMetadata(from url: URL) {
    do {
      try extractFileMetadata(from: url)
      extractAudioMetadata(from: url)
    } catch {
      debugLog(
        "❌ Sound: Failed to extract metadata for '\(fileName)': \(error.localizedDescription)")
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

    // Since deployment target is iOS 16+, we can use async loading directly
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
        debugLog("❌ Sound: Failed to load metadata asynchronously: \(error)")
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
    debugLog(
      "📊 Sound: Metadata for '\(fileName)' - Channels: \(channelCount ?? 0), Duration: \(duration ?? 0)s, Size: \(fileSize ?? 0) bytes, Format: \(fileFormat ?? "unknown")"
    )
  }
}
