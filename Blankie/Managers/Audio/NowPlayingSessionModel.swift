//
//  NowPlayingSessionModel.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  The observable model the OS 27 NowPlaying framework reads: already-resolved
//  state in, framework types out.

#if canImport(NowPlaying)
  import AppIntents
  import Foundation
  import NowPlaying
  import Observation

  @available(iOS 27, macOS 27, visionOS 27, *)
  @Observable
  @MainActor
  final class NowPlayingSessionModel: @MainActor MediaSessionRepresentable {
    /// One session per app; the bundle id keeps it distinct from other apps'.
    let id = (Bundle.main.bundleIdentifier ?? "com.codybrom.blankie") + ".nowplaying"

    var title = ""
    var subtitle: String?
    var contentID = "default"
    var playback: SessionPlayback = .paused
    var timer: SessionTimer?

    // Artwork is held type-erased. A stored `Artwork?` would put a resilient
    // NowPlaying struct in this class's field layout, and completing that layout
    // needs the framework's metadata — which macOS 26 doesn't ship. Anything
    // that realizes every Objective-C class (XCTest does at startup) would then
    // crash on a supported OS. An existential box is pointer-sized, so the
    // framework types are only resolved when these accessors actually run.
    private var artworkBox: Any?
    var artwork: Artwork? {
      get { artworkBox as? Artwork }
      set { artworkBox = newValue }
    }
    #if os(iOS)
      private var animatedArtworkBox: Any?
      var animatedArtwork: AnimatedArtwork? {
        get { animatedArtworkBox as? AnimatedArtwork }
        set { animatedArtworkBox = newValue }
      }
    #endif
    var entityIdentifiers: [EntityIdentifier] = []
    var handlers: RemoteCommandHandlers?
    var navigationEnabled = false

    var content: (any MediaContentRepresentable)? {
      var content = makeContent()
      content.appEntityIdentifiers = entityIdentifiers
      return content
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
      let state: MediaPlaybackSnapshot.PlaybackState =
        switch playback {
        case .playing: .playing()
        case .paused: .paused
        }
      guard let timer else { return MediaPlaybackSnapshot(state: state) }
      return MediaPlaybackSnapshot(
        state: state, elapsedTime: timer.elapsed, timestamp: timer.timestamp)
    }

    var commands: [MediaCommand] { [] }

    private func makeContent() -> GenericContent {
      #if os(iOS)
        if let artwork, let animatedArtwork {
          return GenericContent(
            id: contentID, title: title, subtitle: subtitle, type: .audio,
            duration: mediaDuration, artwork: artwork, animatedArtwork: animatedArtwork)
        }
      #endif
      return GenericContent(
        id: contentID, title: title, subtitle: subtitle, type: .audio,
        duration: mediaDuration, artwork: artwork)
    }

    private var mediaDuration: MediaDuration {
      switch NowPlayingSessionMapping.duration(timer: timer) {
      case .continuous: .continuous
      case .finite(let seconds): .finite(seconds)
      }
    }
  }
#endif
