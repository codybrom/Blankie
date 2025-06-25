//
//  AudioManager+ThreadSafety.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import Foundation

extension AudioManager {
  /// Thread-safe wrapper for updating Now Playing info
  /// Can be called from any thread/actor context
  public func safeUpdateNowPlayingInfo(
    presetName: String? = nil, creatorName: String? = nil, artworkId: UUID? = nil
  ) {
    Task { @MainActor in
      self.updateNowPlayingInfoForPreset(
        presetName: presetName,
        creatorName: creatorName,
        artworkId: artworkId
      )
    }
  }

  /// Thread-safe wrapper for setting playback state
  /// Can be called from any thread/actor context
  public func safeSetGlobalPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    Task { @MainActor in
      self.setGlobalPlaybackState(playing, forceUpdate: forceUpdate)
    }
  }
}
