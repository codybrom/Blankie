//
//  CustomSoundManager+Conversion.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/26.
//
//  Opt-in re-encoding of an imported custom sound to AAC (.m4a), offered from the
//  editor's Format and File Size rows when the file is worth shrinking. The bit rate
//  matches the built-in library (192 kbps).
//

import AVFoundation
import CoreMedia
import Foundation
import os

extension CustomSoundManager {
  /// AAC bit rate for runtime conversion, matching the built-in library.
  nonisolated static let conversionBitRate = 192_000

  /// Lossy formats are never re-encoded (quality loss for little saving), so conversion
  /// is offered only for uncompressed or lossless sources (WAV, AIFF, CAF, FLAC).
  private static let lossyExtensions: Set<String> = ["mp3", "m4a", "aac", "m4b", "aax", "m4r"]

  /// AAC and MP3 codecs. Checked by codec because an .m4a can also hold Apple Lossless.
  private static let lossyFormatIDs: Set<AudioFormatID> = [
    kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
    kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEGLayer3,
  ]

  /// True when an import must be transcoded: a file over `maxRawImportBytes` whose audio
  /// isn't already AAC or MP3. Re-encoding a lossy file costs time and quality and saves
  /// little. A file AVAudioFile can't open is converted, as before.
  static func importRequiresConversion(bytes: Int64, url: URL) -> Bool {
    guard bytes > maxRawImportBytes else { return false }
    let formatID = (try? AVAudioFile(forReading: url))?.fileFormat.settings[AVFormatIDKey]
    return (formatID as? AudioFormatID).map { !lossyFormatIDs.contains($0) } ?? true
  }

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
    // A malformed file's duration can be infinite, and Int64(_:) traps on it.
    guard
      let projected = Int64(
        exactly: (Double(Self.conversionBitRate) / 8.0 * duration).rounded(.down))
    else { return nil }
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

  /// Re-encodes a custom sound's file as AAC (.m4a) in place and refreshes the live
  /// sound instance. The original is removed only after the new file is written.
  @MainActor
  func convertToAAC(soundDataID: UUID) async -> Result<CompressionEstimate, ConversionError> {
    guard let data = getCustomSound(by: soundDataID) else { return .failure(.soundNotFound) }
    guard let sourceURL = getURLForCustomSound(data), let dir = getCustomSoundsDirectoryURL() else {
      return .failure(.soundNotFound)
    }

    let beforeBytes = fileSize(at: sourceURL)
    // Unique per run, so a second conversion of the same sound can never unlink (or
    // swap in) this run's half-written file.
    let tempURL = dir.appendingPathComponent("\(data.fileName)-aac-\(UUID().uuidString).m4a")

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

    // The sound may have been deleted during the transcode. If so, don't move an
    // orphan file into place or save the deleted model.
    guard getCustomSound(by: soundDataID) != nil else {
      try? FileManager.default.removeItem(at: tempURL)
      return .failure(.soundNotFound)
    }

    // Release the live player so its file handle drops before the swap. The sound is
    // then refreshed in place.
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
      // Repoint the existing instance so observers see the new format and size. The
      // player is rebuilt only if it was loaded (resuming if it was playing).
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
      // No instance yet. Load just this one so the others aren't rebuilt.
      AudioManager.shared.loadCustomSoundsByIds([soundDataID])
    }

    Logger.sounds.debug(
      "CustomSoundManager: converted \(data.fileName, privacy: .public) to AAC (\(beforeBytes) -> \(afterBytes) bytes)"
    )
    return .success(CompressionEstimate(currentBytes: beforeBytes, projectedBytes: afterBytes))
  }

  private func fileSize(at url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
  }

  /// Streams `source` through an AAC encoder into `destination` (.m4a) at the library
  /// bit rate, keeping memory bounded. Static so it runs off the main actor without
  /// sending `self`. importSound also uses it for oversized imports. `progress`
  /// receives the fraction encoded, from 0 to 1. Cancelling the task stops the encode
  /// and throws `CancellationError`.
  @concurrent static func transcodeToAAC(
    source: URL, destination: URL, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let asset = AVURLAsset(url: source)
    let totalSeconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
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
    // AAC encodes only a fixed set of sample rates (up to 48 kHz), and the writer
    // crashes at init on others, so resample anything else (a 96 kHz FLAC) to 44.1 kHz.
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
    // AAC needs an explicit channel layout above stereo, so carry the source's over.
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
    // Touched only on `queue`, like the reader and writer.
    nonisolated(unsafe) var nextReport = 0.0
    let cancelled = OSAllocatedUnfairLock(initialState: false)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        writerInput.requestMediaDataWhenReady(on: queue) {
          while writerInput.isReadyForMoreMediaData {
            if cancelled.withLock({ $0 }) {
              reader.cancelReading()
              writer.cancelWriting()
              continuation.resume(throwing: CancellationError())
              return
            }
            if reader.status == .reading, let buffer = readerOutput.copyNextSampleBuffer() {
              if let progress, totalSeconds > 0 {
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                if seconds >= nextReport {
                  progress(min(seconds / totalSeconds, 1))
                  nextReport = seconds + totalSeconds / 100
                }
              }
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
    } onCancel: {
      cancelled.withLock { $0 = true }
    }
  }
}
