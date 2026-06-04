//
//  CustomSoundManager+Metadata.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import AVFoundation
import Foundation
import os

// MARK: - ID3 Metadata Extraction

extension CustomSoundManager {
  struct AudioMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var comment: String?
    var url: String?
  }

  /// Extract comprehensive metadata from audio file including ID3 tags
  func extractAudioMetadata(from url: URL) async -> AudioMetadata {
    var metadata = AudioMetadata()

    do {
      let asset = AVURLAsset(url: url)

      // Process common metadata
      let commonMetadata = try await asset.load(.commonMetadata)
      metadata = await processCommonMetadata(commonMetadata, metadata)

      // Process format-specific metadata
      let formatMetadata = try await asset.load(.metadata)
      metadata = await processFormatMetadata(formatMetadata, metadata)

      logExtractedMetadata(metadata)
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to extract metadata: \(error, privacy: .public)")
    }

    return metadata
  }

  private func processCommonMetadata(_ items: [AVMetadataItem], _ metadata: AudioMetadata) async
    -> AudioMetadata
  {
    var result = metadata

    for item in items {
      guard let key = item.commonKey else { continue }
      guard let value = try? await item.load(.value) else { continue }

      switch key {
      case .commonKeyTitle:
        result.title = extractStringValue(from: value)
      case .commonKeyArtist:
        result.artist = extractStringValue(from: value)
      case .commonKeyAlbumName:
        result.album = extractStringValue(from: value)
      case .commonKeyDescription:
        result.comment = extractStringValue(from: value)
      default:
        if let urlString = extractStringValue(from: value),
          isValidURL(urlString)
        {
          result.url = urlString
        }
      }
    }

    return result
  }

  private func processFormatMetadata(_ items: [AVMetadataItem], _ metadata: AudioMetadata) async
    -> AudioMetadata
  {
    var result = metadata

    for item in items {
      guard let identifier = item.identifier else { continue }
      let idString = identifier.rawValue

      if isURLIdentifier(idString) && result.url == nil {
        if let urlValue = try? await item.load(.value),
          let urlString = extractStringValue(from: urlValue)
        {
          result.url = urlString
        }
      } else if isCommentIdentifier(idString) && result.comment == nil {
        if let commentValue = try? await item.load(.value) {
          result.comment = extractStringValue(from: commentValue)
        }
      }
    }

    return result
  }

  private func isValidURL(_ string: String) -> Bool {
    return string.hasPrefix("http://") || string.hasPrefix("https://")
  }

  private func isURLIdentifier(_ idString: String) -> Bool {
    let urlIdentifiers = ["WOAR", "WOAF", "WOAS", "WORS", "WPUB", "WXXX"]
    return urlIdentifiers.contains { idString.contains($0) }
  }

  private func isCommentIdentifier(_ idString: String) -> Bool {
    return idString.contains("COMM") || idString.contains("comment")
  }

  private func logExtractedMetadata(_ metadata: AudioMetadata) {
    Logger.sounds.debug("CustomSoundManager: Extracted metadata:")
    Logger.sounds.debug("   Title: \(metadata.title ?? "none")")
    Logger.sounds.debug("   Artist: \(metadata.artist ?? "none")")
    Logger.sounds.debug("   Album: \(metadata.album ?? "none")")
    Logger.sounds.debug("   Comment: \(metadata.comment ?? "none")")
    Logger.sounds.debug("   URL: \(metadata.url ?? "none")")
  }

  private func extractStringValue(from value: Any) -> String? {
    if let stringValue = value as? String {
      let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    } else if let data = value as? Data,
      let stringValue = String(data: data, encoding: .utf8)
    {
      let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }
}
