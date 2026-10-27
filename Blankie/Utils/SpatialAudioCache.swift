//
//  SpatialAudioCache.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import Foundation
import os

/// Rendered mono variants of long sounds, so streamed playback can join the
/// spatial field (the environment node spatializes only mono). Keyed by source
/// name and baked boost, so a re-analysis renders a fresh variant in Caches.
nonisolated enum SpatialAudioCache {

  private static var directory: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SpatialAudio", isDirectory: true)
  }

  static func cacheURL(for sourceURL: URL, boostDB: Float) -> URL {
    let name = "\(sourceURL.lastPathComponent)-\(String(format: "%.1f", boostDB))dB.m4a"
    return directory.appendingPathComponent(name)
  }

  /// The rendered mono cache for this source, if one exists.
  static func existingCache(for sourceURL: URL, boostDB: Float) -> URL? {
    let url = cacheURL(for: sourceURL, boostDB: boostDB)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// Removes every rendered variant of this source (any boost). Called when a
  /// custom sound is deleted.
  static func removeCaches(for sourceURL: URL) {
    let prefix = "\(sourceURL.lastPathComponent)-"
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return }
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  /// Renders (or returns) the mono cache: chunked fold to mono with the
  /// normalization boost baked in, written as AAC. Runs off the main thread.
  static func renderMonoCache(for sourceURL: URL, boostDB: Float) async throws -> URL {
    let destination = cacheURL(for: sourceURL, boostDB: boostDB)
    if FileManager.default.fileExists(atPath: destination.path) {
      return destination
    }

    return try await Task.detached(priority: .userInitiated) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let inFile = try AVAudioFile(forReading: sourceURL)
      // Refuse a zero-frame source because its empty cache would read as valid.
      guard inFile.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
      let inFormat = inFile.processingFormat

      // Write to a temp file first so a cancelled render never leaves a
      // half-written cache behind.
      let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spatial-render-\(UUID().uuidString).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: inFormat.sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
      ]
      let outFile = try AVAudioFile(forWriting: tempURL, settings: settings)

      let chunkFrames: AVAudioFrameCount = 48_000
      while inFile.framePosition < inFile.length {
        // Clamp before narrowing, since the remainder alone can exceed UInt32.
        let frames = AVAudioFrameCount(
          min(AVAudioFramePosition(chunkFrames), inFile.length - inFile.framePosition))
        guard
          let chunk = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames)
        else { throw CocoaError(.fileReadUnknown) }
        try inFile.read(into: chunk, frameCount: frames)

        guard let mono = SoundPlayer.monoFold(of: chunk, gainDB: boostDB) else {
          throw CocoaError(.fileReadUnknown)
        }
        try outFile.write(from: mono)
      }

      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: tempURL, to: destination)
      Logger.sounds.debug(
        "SpatialAudioCache: Rendered mono cache for '\(sourceURL.lastPathComponent)'")
      return destination
    }.value
  }
}
