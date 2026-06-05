//
//  AudioError.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import SwiftUI

enum AudioError: Error, LocalizedError {
  case fileNotFound
  case loadFailed(Error)
  case playbackFailed(Error)
  case invalidVolume
  case systemAudioError(String)
  case engineStartFailed

  var errorDescription: String? {
    switch self {
    case .engineStartFailed:
      return "Audio engine failed to start"
    case .fileNotFound:
      return "Audio file could not be found"
    case .loadFailed(let error):
      return "Failed to load audio: \(error.localizedDescription)"
    case .playbackFailed(let error):
      return "Playback failed: \(error.localizedDescription)"
    case .invalidVolume:
      return "Invalid volume level specified"
    case .systemAudioError(let message):
      return "System audio error: \(message)"
    }
  }
}
