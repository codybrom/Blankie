//
//  CustomSoundManager+Conversion.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/26.
//
//  Opt-in re-encoding of an imported custom sound to AAC (.m4a) to reclaim
//  space. Offered (never automatic) from the editor's Format / File Size rows
//  when the file is worth shrinking. The bit rate matches the built-in library
//  (blankifi encodes built-ins at 192 kbps), so a converted sound sits at the
//  same quality as everything else.
//

import AVFoundation
import CoreMedia
import Foundation
import os

extension CustomSoundManager {
  /// AAC bit rate for runtime conversion, matching the built-in library.
  nonisolated static let conversionBitRate = 192_000

  /// Lossy formats we never re-encode. Re-encoding already-compressed audio
  /// loses quality for little or no space saving, so conversion is only offered
  /// for uncompressed or lossless sources (WAV, AIFF, CAF, FLAC, and the like).
  private static let lossyExtensions: Set<String> = ["mp3", "m4a", "aac", "m4b", "aax", "m4r"]

  /// The before and after of an offered conversion, in bytes.
  struct CompressionEstimate: Equatable {
    let currentBytes: Int64
    let projectedBytes: Int64
    var savedBytes: Int64 { max(0, currentBytes - projectedBytes) }
    var savedFraction: Double {
      currentBytes > 0 ? Double(savedBytes) / Double(currentBytes) : 0
    }
  }

  /// Whether converting to AAC is worth offering, and the numbers to show. Returns
  /// an estimate when the file isn't already a lossy format, is over 5 MB, and AAC
  /// would shave off more than half. Returns nil when the sound is already efficient.
  func compressionEstimate(
    forExtension ext: String, currentBytes: Int64?, duration: TimeInterval?
  ) -> CompressionEstimate? {
    guard !Self.lossyExtensions.contains(ext.lowercased()) else { return nil }
    guard let currentBytes, currentBytes > 5 * 1024 * 1024 else { return nil }
    guard let duration, duration > 0 else { return nil }
    let projected = Int64(Double(Self.conversionBitRate) / 8.0 * duration)
    let estimate = CompressionEstimate(currentBytes: currentBytes, projectedBytes: projected)
    guard estimate.savedFraction > 0.5 else { return nil }
    return estimate
  }

  enum ConversionError: LocalizedError {
    case soundNotFound
    case noAudioTrack
    case encodingFailed
    case noSavings

    var errorDescription: String? {
      switch self {
      case .soundNotFound:
        return String(localized: "This sound's file couldn't be found.")
      case .noAudioTrack:
        return String(localized: "This file doesn't contain audio that can be converted.")
      case .encodingFailed:
        return String(localized: "The audio couldn't be converted. The original is unchanged.")
      case .noSavings:
        return String(localized: "Converting wouldn't save space, so the original was kept.")
      }
    }
  }

  /// Re-encodes a custom sound's file as AAC (.m4a) in place, replacing the
  /// original, then refreshes the live sound instance so the open editor and the
  /// grid update without a list rebuild. The original is only removed once the
  /// new file is written, so a failure leaves the sound untouched.
  @MainActor
  func convertToAAC(soundDataID: UUID) async -> Result<CompressionEstimate, ConversionError> {
    guard let data = getCustomSound(by: soundDataID) else { return .failure(.soundNotFound) }
    guard let sourceURL = getURLForCustomSound(data), let dir = getCustomSoundsDirectoryURL() else {
      return .failure(.soundNotFound)
    }

    let beforeBytes = fileSize(at: sourceURL)
    let tempURL = dir.appendingPathComponent("\(data.fileName)-aac-tmp.m4a")
    try? FileManager.default.removeItem(at: tempURL)

    do {
      try await Self.transcodeToAAC(source: sourceURL, destination: tempURL)
    } catch let error as ConversionError {
      try? FileManager.default.removeItem(at: tempURL)
      return .failure(error)
    } catch {
      try? FileManager.default.removeItem(at: tempURL)
      Logger.sounds.error("CustomSoundManager: AAC conversion failed: \(error, privacy: .public)")
      return .failure(.encodingFailed)
    }

    let afterBytes = fileSize(at: tempURL)
    guard afterBytes > 0, afterBytes < beforeBytes else {
      try? FileManager.default.removeItem(at: tempURL)
      return .failure(.noSavings)
    }

    // Release the live player before replacing the file so its handle is dropped
    // and the sound can be refreshed in place — no full list rebuild, so the open
    // editor (and grid) stay coherent. Captured before the swap.
    let liveSound = AudioManager.shared.sounds.first { $0.customSoundDataID == soundDataID }
    let wasPlaying = liveSound?.playbackState == .playing
    let wasLoaded = liveSound?.isLoaded ?? false
    liveSound?.unload()

    // Swap the new file into place and drop the original. Only happens after a
    // verified-smaller encode, so the sound is never left without a file.
    let finalURL = dir.appendingPathComponent("\(data.fileName).m4a")
    do {
      if FileManager.default.fileExists(atPath: finalURL.path) {
        try FileManager.default.removeItem(at: finalURL)
      }
      try FileManager.default.moveItem(at: tempURL, to: finalURL)
      if sourceURL.standardizedFileURL != finalURL.standardizedFileURL {
        try? FileManager.default.removeItem(at: sourceURL)
        // The rendered spatial mono variants were keyed to the old file.
        SpatialAudioCache.removeCaches(for: sourceURL)
      }
      data.fileExtension = "m4a"
      try saveContext()
    } catch {
      try? FileManager.default.removeItem(at: tempURL)
      Logger.sounds.error("CustomSoundManager: AAC swap failed: \(error, privacy: .public)")
      return .failure(.encodingFailed)
    }

    if let liveSound {
      // Repoint the existing instance at the new file. Observers (editor, grid)
      // see the format/size update without a rebuild. Rebuild the player only if
      // it was loaded, resuming playback if it was playing; otherwise just
      // refresh the displayed metadata.
      liveSound.fileExtension = "m4a"
      liveSound.fileURL = finalURL
      if wasLoaded || wasPlaying {
        liveSound.loadSound()
        if wasPlaying { liveSound.play() }
      } else {
        liveSound.extractMetadata(from: finalURL)
      }
      // Re-measure loudness on the new bytes and overwrite the stored profile
      // (keyed by the unchanged file name).
      await liveSound.reanalyzeAudio()
    } else {
      // Not currently loaded — fall back to a full reload so the record's new
      // extension is picked up.
      AudioManager.shared.loadCustomSounds()
    }

    Logger.sounds.debug(
      "CustomSoundManager: converted \(data.fileName, privacy: .public) to AAC (\(beforeBytes) -> \(afterBytes) bytes)"
    )
    return .success(CompressionEstimate(currentBytes: beforeBytes, projectedBytes: afterBytes))
  }

  private func fileSize(at url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
  }

  /// Streams `source` through an AAC encoder into `destination` (.m4a) at the
  /// library bit rate, preserving the source's sample rate and channels.
  /// Streaming keeps memory bounded for long files. Stateless (no instance use)
  /// so it can run off the main actor without sending `self` across the boundary.
  /// Reused by importSound to force oversized imports to AAC.
  @concurrent static func transcodeToAAC(source: URL, destination: URL) async throws {
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw ConversionError.noAudioTrack
    }
    let formatDescriptions = try await track.load(.formatDescriptions)
    guard let formatDesc = formatDescriptions.first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
    else {
      throw ConversionError.noAudioTrack
    }
    let channels = Int(asbd.mChannelsPerFrame)
    // AAC only encodes a fixed set of sample rates (up to 48 kHz). Keep the
    // source rate when it's already one of those, otherwise resample to the
    // library's 44.1 kHz. Without this a hi-res source (e.g. a 96 kHz FLAC)
    // crashes the AAC writer at init.
    let validAACSampleRates: Set<Double> = [
      8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
    ]
    let sampleRate = validAACSampleRates.contains(asbd.mSampleRate) ? asbd.mSampleRate : 44100

    // These AVFoundation objects aren't Sendable, but they're created here and
    // only ever touched on the single serial queue driving the pump below, so
    // sharing them into that @Sendable closure is safe.
    nonisolated(unsafe) let reader = try AVAssetReader(asset: asset)
    nonisolated(unsafe) let readerOutput = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
        // Resample to the AAC-safe rate so the PCM fed to the writer matches.
        AVSampleRateKey: sampleRate,
      ])
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else { throw ConversionError.encodingFailed }
    reader.add(readerOutput)

    var writerSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channels,
      AVEncoderBitRateKey: Self.conversionBitRate,
    ]
    // AAC needs an explicit channel layout above stereo; carry the source's over.
    var layoutSize = 0
    if let layoutPtr = CMAudioFormatDescriptionGetChannelLayout(formatDesc, sizeOut: &layoutSize),
      layoutSize > 0
    {
      writerSettings[AVChannelLayoutKey] = Data(bytes: layoutPtr, count: layoutSize)
    } else if channels > 2 {
      throw ConversionError.encodingFailed
    }

    nonisolated(unsafe) let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
    nonisolated(unsafe) let writerInput = AVAssetWriterInput(
      mediaType: .audio, outputSettings: writerSettings)
    writerInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(writerInput) else { throw ConversionError.encodingFailed }
    writer.add(writerInput)

    guard reader.startReading(), writer.startWriting() else {
      throw ConversionError.encodingFailed
    }
    writer.startSession(atSourceTime: .zero)

    let queue = DispatchQueue(label: "com.codybrom.blankie.aac-convert")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
          if reader.status == .reading, let buffer = readerOutput.copyNextSampleBuffer() {
            if !writerInput.append(buffer) {
              reader.cancelReading()
              writer.cancelWriting()
              continuation.resume(throwing: ConversionError.encodingFailed)
              return
            }
          } else {
            // A nil buffer means the reader is drained (or it stopped). Finalize.
            writerInput.markAsFinished()
            if reader.status == .failed {
              writer.cancelWriting()
              continuation.resume(throwing: ConversionError.encodingFailed)
            } else {
              writer.finishWriting {
                if writer.status == .completed {
                  continuation.resume()
                } else {
                  continuation.resume(throwing: ConversionError.encodingFailed)
                }
              }
            }
            return
          }
        }
      }
    }
  }
}
