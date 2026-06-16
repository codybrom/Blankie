//
//  EngineRenderHarness.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFoundation
import AudioToolbox

/// Errors surfaced by the offline rendering harness.
enum EngineRenderError: Error, CustomStringConvertible {
  case bufferAllocationFailed
  case limiterUnavailable(OSStatus)
  case renderFailed(AVAudioEngineManualRenderingStatus)
  case fileTooShort

  var description: String {
    switch self {
    case .bufferAllocationFailed: return "Failed to allocate a render/output buffer"
    case .limiterUnavailable(let status):
      return "PeakLimiter AU failed to instantiate (OSStatus \(status))"
    case .renderFailed(let status):
      return "renderOffline returned an unexpected status (\(status.rawValue))"
    case .fileTooShort: return "Source file has zero frames"
    }
  }
}

/// Offline manual-rendering harness mirroring the planned engine graph
/// (player → EQ globalGain → [limiter] → mixer → output), so loudness/seam
/// tests can measure rendered audio with the production AudioAnalyzer math.
enum EngineRenderHarness {

  /// Instantiates Apple's PeakLimiter AU, or throws so the loudness test can
  /// skip (via `Test.cancel`) when the AU is unavailable in manual rendering.
  static func makeLimiter() throws -> AVAudioUnit {
    var description = AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_PeakLimiter,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0)

    guard AudioComponentFindNext(nil, &description) != nil else {
      throw EngineRenderError.limiterUnavailable(-1)
    }

    var result: Result<AVAudioUnit, Error>?
    let semaphore = DispatchSemaphore(value: 0)
    AVAudioUnit.instantiate(with: description, options: []) { unit, error in
      if let unit {
        result = .success(unit)
      } else {
        let code = OSStatus(truncatingIfNeeded: (error as NSError?)?.code ?? -2)
        result = .failure(EngineRenderError.limiterUnavailable(code))
      }
      semaphore.signal()
    }
    // Bound the wait so a stuck instantiation surfaces as a skip, not a hang.
    _ = semaphore.wait(timeout: .now() + 5)

    switch result {
    case .success(let unit): return unit
    case .failure(let error): throw error
    case .none: throw EngineRenderError.limiterUnavailable(-3)
    }
  }

  /// Renders `fileURL` offline through the planned graph, returning exactly
  /// `seconds` of audio in the file's processing format. Loops by scheduling
  /// the file twice when `seconds` exceeds the file's own duration.
  static func render(
    fileURL: URL,
    boostDB: Float,
    attenuation: Float,
    seconds: Double,
    throughLimiter: Bool
  ) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: fileURL)
    let format = file.processingFormat
    let fileLength = file.length
    guard fileLength > 0 else { throw EngineRenderError.fileTooShort }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 0)
    eq.globalGain = boostDB

    engine.attach(player)
    engine.attach(eq)

    let limiter: AVAudioUnit?
    if throughLimiter {
      let unit = try makeLimiter()
      engine.attach(unit)
      limiter = unit
    } else {
      limiter = nil
    }

    // Mirror production wiring (AudioEngineManager): per-sound chain feeds the
    // main mixer, and the limiter sits on the mix bus after it — so the
    // limiter sees post-pan-law levels, exactly as it does in the app.
    let mixer = engine.mainMixerNode
    engine.connect(player, to: eq, format: format)
    engine.connect(eq, to: mixer, format: format)
    if let limiter {
      engine.connect(mixer, to: limiter, format: nil)
      engine.connect(limiter, to: engine.outputNode, format: nil)
    }

    player.volume = attenuation

    let maxFrames: AVAudioFrameCount = 4096
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)

    let fileDuration = Double(fileLength) / format.sampleRate
    player.scheduleFile(file, at: nil)
    if seconds > fileDuration {
      // Re-open so the second pass reads from frame 0 independently; the loop
      // seam frame is therefore exactly fileLength.
      let secondPass = try AVAudioFile(forReading: fileURL)
      player.scheduleFile(secondPass, at: nil)
    }

    try engine.start()
    player.play()

    let targetFrames = AVAudioFrameCount(seconds * format.sampleRate)
    guard
      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: targetFrames),
      let renderBuffer = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)
    else {
      throw EngineRenderError.bufferAllocationFailed
    }

    var rendered: AVAudioFrameCount = 0
    while rendered < targetFrames {
      let toRender = min(maxFrames, targetFrames - rendered)
      let status = try engine.renderOffline(toRender, to: renderBuffer)

      switch status {
      case .success:
        appendFrames(from: renderBuffer, to: output)
        rendered += renderBuffer.frameLength
      case .insufficientDataFromInputNode:
        // Player ran dry; zero-pad the tail so callers get the full length.
        appendFrames(from: renderBuffer, to: output)
        rendered += renderBuffer.frameLength
        if renderBuffer.frameLength == 0 {
          padSilence(to: output, upTo: targetFrames)
          rendered = targetFrames
        }
      case .cannotDoInCurrentContext:
        continue
      case .error:
        engine.stop()
        throw EngineRenderError.renderFailed(status)
      @unknown default:
        engine.stop()
        throw EngineRenderError.renderFailed(status)
      }
    }

    player.stop()
    engine.stop()
    output.frameLength = targetFrames
    return output
  }

  // MARK: - Buffer plumbing

  private static func appendFrames(
    from source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer
  ) {
    let frames = source.frameLength
    guard frames > 0,
      let src = source.floatChannelData,
      let dst = destination.floatChannelData
    else { return }

    let offset = Int(destination.frameLength)
    let channels = Int(min(source.format.channelCount, destination.format.channelCount))
    for channel in 0..<channels {
      dst[channel].advanced(by: offset).update(from: src[channel], count: Int(frames))
    }
    destination.frameLength += frames
  }

  private static func padSilence(to buffer: AVAudioPCMBuffer, upTo target: AVAudioFrameCount) {
    guard buffer.frameLength < target, let data = buffer.floatChannelData else { return }
    let start = Int(buffer.frameLength)
    let count = Int(target - buffer.frameLength)
    for channel in 0..<Int(buffer.format.channelCount) {
      data[channel].advanced(by: start).update(repeating: 0, count: count)
    }
    buffer.frameLength = target
  }
}
