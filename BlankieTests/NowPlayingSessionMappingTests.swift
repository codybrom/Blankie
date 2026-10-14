//
//  NowPlayingSessionMappingTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 9/15/26.
//
//  The OS 27 session's pure mappings: playback state, sleep-timer progress,
//  duration, and the content identity that has to stay stable across
//  incremental updates so the system doesn't restart the card.
//

import Foundation
import Testing

@testable import Blankie

@Suite struct NowPlayingSessionMappingTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  // MARK: - Playback

  @Test func playingMapsToPlaying() {
    #expect(NowPlayingSessionMapping.playback(isPlaying: true) == .playing)
  }

  @Test func notPlayingMapsToPaused() {
    #expect(NowPlayingSessionMapping.playback(isPlaying: false) == .paused)
  }

  // MARK: - Timer

  @Test func inactiveTimerHasNoProgress() {
    #expect(
      NowPlayingSessionMapping.timer(
        isActive: false, selectedDuration: 1200, remainingTime: 900, now: now) == nil)
  }

  @Test func zeroDurationTimerHasNoProgress() {
    #expect(
      NowPlayingSessionMapping.timer(
        isActive: true, selectedDuration: 0, remainingTime: 0, now: now) == nil)
  }

  @Test func elapsedIsDurationMinusRemaining() throws {
    let timer = try #require(
      NowPlayingSessionMapping.timer(
        isActive: true, selectedDuration: 1200, remainingTime: 900, now: now))
    #expect(timer.duration == 1200)
    #expect(timer.elapsed == 300)
    #expect(timer.timestamp == now)
  }

  @Test func elapsedClampsAtZero() throws {
    // A remaining time above the total (an extended timer mid-update) must not
    // publish a negative elapsed.
    let timer = try #require(
      NowPlayingSessionMapping.timer(
        isActive: true, selectedDuration: 1200, remainingTime: 1500, now: now))
    #expect(timer.elapsed == 0)
  }

  @Test func elapsedClampsAtDuration() throws {
    let timer = try #require(
      NowPlayingSessionMapping.timer(
        isActive: true, selectedDuration: 1200, remainingTime: -30, now: now))
    #expect(timer.elapsed == 1200)
  }

  // MARK: - Duration

  @Test func noTimerIsContinuous() {
    #expect(NowPlayingSessionMapping.duration(timer: nil) == .continuous)
  }

  @Test func runningTimerIsFinite() {
    let timer = NowPlayingSessionMapping.SessionTimer(duration: 1800, elapsed: 60, timestamp: now)
    #expect(NowPlayingSessionMapping.duration(timer: timer) == .finite(1800))
  }

  // MARK: - Content identity

  @Test func soloWinsOverEverything() {
    #expect(
      NowPlayingSessionMapping.contentID(
        soloFileName: "rain", isQuickMix: true, presetID: UUID()) == "solo:rain")
  }

  @Test func quickMixWinsOverPreset() {
    #expect(
      NowPlayingSessionMapping.contentID(
        soloFileName: nil, isQuickMix: true, presetID: UUID()) == "quickmix")
  }

  @Test func presetUsesItsIdentifier() {
    let id = UUID()
    #expect(
      NowPlayingSessionMapping.contentID(soloFileName: nil, isQuickMix: false, presetID: id)
        == "preset:\(id.uuidString)")
  }

  @Test func nothingActiveFallsBackToDefault() {
    #expect(
      NowPlayingSessionMapping.contentID(soloFileName: nil, isQuickMix: false, presetID: nil)
        == "default")
  }

  /// A running sleep timer publishes under its own id, and the base id comes
  /// back untouched when it ends.
  @Test func timedContentIDIsSuffixedOnlyWhileATimerRuns() {
    #expect(NowPlayingSessionMapping.contentID("quickmix", timed: true) == "quickmix:timed")
    #expect(NowPlayingSessionMapping.contentID("quickmix", timed: false) == "quickmix")
  }

  // MARK: - Artwork identity

  @Test func storedArtworkUsesItsIdentifier() {
    let id = UUID()
    #expect(
      NowPlayingSessionMapping.artworkID(source: .stored(id), accentColorName: "blue")
        == "artwork:\(id.uuidString)")
  }

  @Test func fileArtworkUsesItsPath() {
    #expect(
      NowPlayingSessionMapping.artworkID(source: .file("previews/rain.jpg"), accentColorName: nil)
        == "static:previews/rain.jpg")
  }

  @Test func bundledArtworkUsesItsIdentifier() {
    #expect(
      NowPlayingSessionMapping.artworkID(source: .bundled("OceanWaves"), accentColorName: nil)
        == "bundled:OceanWaves")
  }

  @Test func soloArtworkFoldsInTheAccent() {
    // The soloed sound's card is drawn in the accent, so two accents have to be
    // two ids — the system never re-requests an id it already cached.
    #expect(
      NowPlayingSessionMapping.artworkID(source: .solo(fileName: "rain"), accentColorName: "teal")
        == "solo:rain:teal")
  }

  @Test func missingAccentFallsBackToDefault() {
    #expect(
      NowPlayingSessionMapping.artworkID(source: .solo(fileName: "rain"), accentColorName: nil)
        == "solo:rain:default")
  }

  @Test func fallbackArtworkFoldsInKindAccentAndIcons() {
    #expect(
      NowPlayingSessionMapping.artworkID(
        source: .fallback(kind: "composite", icons: ["cloud.rain", "wind"]),
        accentColorName: "indigo") == "fallback:composite:indigo:cloud.rain,wind")
  }

  @Test func fallbackArtworkWithoutIconsEndsEmpty() {
    #expect(
      NowPlayingSessionMapping.artworkID(
        source: .fallback(kind: "brand", icons: []), accentColorName: nil)
        == "fallback:brand:default:")
  }

  @Test func differentIconsGiveDifferentArtworkIdentities() {
    let one = NowPlayingSessionMapping.artworkID(
      source: .fallback(kind: "composite", icons: ["cloud.rain"]), accentColorName: "blue")
    let two = NowPlayingSessionMapping.artworkID(
      source: .fallback(kind: "composite", icons: ["wind"]), accentColorName: "blue")
    #expect(one != two)
  }

  // MARK: - Aspect ratios

  @Test func supportedRatiosKeepTheDeviceOrder() {
    #expect(
      NowPlayingSessionMapping.supportedRatios(
        compatible: [.tall, .square], available: [.square, .tall]) == [.tall, .square])
  }

  @Test func supportedRatiosDropWhatHasNoLoop() {
    #expect(
      NowPlayingSessionMapping.supportedRatios(compatible: [.square, .tall], available: [.tall])
        == [.tall])
  }

  @Test func supportedRatiosIgnoreWhatTheDeviceCannotShow() {
    #expect(
      NowPlayingSessionMapping.supportedRatios(compatible: [.square], available: [.square, .tall])
        == [.square])
  }

  @Test func noCompatibleRatiosPublishNothing() {
    #expect(
      NowPlayingSessionMapping.supportedRatios(compatible: [], available: [.square]).isEmpty)
  }

  // MARK: - Animated artwork identity

  @Test func animatedArtworkPrefersTheLoopKey() {
    #expect(
      NowPlayingSessionMapping.animatedArtworkID(loopKey: "OceanWaves", presetID: UUID())
        == "OceanWaves")
  }

  @Test func animatedArtworkFallsBackToThePresetIdentifier() {
    let id = UUID()
    #expect(
      NowPlayingSessionMapping.animatedArtworkID(loopKey: nil, presetID: id) == id.uuidString)
  }
}
