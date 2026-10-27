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
    var playback: NowPlayingSessionMapping.SessionPlayback = .paused
    var timer: NowPlayingSessionMapping.SessionProgress?
    var loopProgress: NowPlayingSessionMapping.SessionProgress?

    // Artwork is type-erased: a stored `Artwork?` puts a resilient NowPlaying struct
    // in the field layout, which needs framework metadata macOS 26 lacks (XCTest
    // realizes every class at startup). A pointer-sized box defers that to the accessors.
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
      guard let progress = timer ?? loopProgress else { return MediaPlaybackSnapshot(state: state) }
      return MediaPlaybackSnapshot(
        state: state, elapsedTime: progress.elapsed, timestamp: progress.timestamp)
    }

    /// The remote commands the session offers. Navigation is enabled only when
    /// there's somewhere to go.
    var commands: [MediaCommand] {
      guard let handlers else { return [] }
      return [
        .play { handlers.play() },
        .pause { handlers.pause() },
        .togglePlayPause { handlers.togglePlayPause() },
        .next { _ = handlers.next() }.enabled(navigationEnabled),
        .previous { _ = handlers.previous() }.enabled(navigationEnabled),
      ]
    }

    private func makeContent() -> GenericContent {
      let id = NowPlayingSessionMapping.contentID(
        contentID, timerDuration: timer?.duration, loopDuration: loopProgress?.duration)
      #if os(iOS)
        if let artwork, let animatedArtwork {
          return GenericContent(
            id: id, title: title, subtitle: subtitle, type: .audio,
            duration: mediaDuration, artwork: artwork, animatedArtwork: animatedArtwork)
        }
      #endif
      return GenericContent(
        id: id, title: title, subtitle: subtitle, type: .audio,
        duration: mediaDuration, artwork: artwork)
    }

    private var mediaDuration: MediaDuration {
      switch NowPlayingSessionMapping.duration(timer: timer, loop: loopProgress) {
      case .continuous: .continuous
      case .finite(let seconds): .finite(seconds)
      }
    }
  }
#endif
