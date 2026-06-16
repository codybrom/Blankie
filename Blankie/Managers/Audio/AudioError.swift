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
      return String(localized: "Audio engine failed to start")
    case .fileNotFound:
      return String(localized: "Audio file could not be found")
    case .loadFailed(let error):
      return String(localized: "Failed to load audio: \(error.localizedDescription)")
    case .playbackFailed(let error):
      return String(localized: "Playback failed: \(error.localizedDescription)")
    case .invalidVolume:
      return String(localized: "Invalid volume level specified")
    case .systemAudioError(let message):
      return String(localized: "System audio error: \(message)")
    }
  }
}
