//
//  WidgetSnapshotTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 7/8/26.
//
//  The cached snapshot the Home Screen widgets and Control Center controls
//  render off the App Group. Covers the encode round-trip and corrupt-data
//  fallback, the publish dedup (identical snapshots skip the write + timeline
//  reload), the shared subtitle rule, and that a favorites change republishes
//  the catalog immediately.
//
//  Serialized + main-actor: mutates the GlobalSettings.shared singleton and the
//  shared "widgetSnapshot" default; each test restores the touched values.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class WidgetSnapshotTests {
  private let settings = GlobalSettings.shared
  private let snapshot = DefaultsSnapshot([
    "widgetSnapshot",
    UserDefaultsKeys.starredItems,
  ])
  private let originalStarred: [String]

  init() {
    originalStarred = settings.starredItems
    settings.starredItems = []
    snapshot.clear()
  }

  isolated deinit {
    settings.starredItems = originalStarred
    snapshot.restore()
  }

  private func makeSnapshot(title: String) -> WidgetSnapshot {
    WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: true, title: title, subtitle: "one, two", soundSystemIconNames: ["cloud"],
        thumbnailKey: nil, activeToken: nil, accentColorName: nil),
      favorites: [],
      quickMixSounds: [],
      pinnableItems: [],
      defaultAccentColorName: nil
    )
  }

  /// Every field of every nested type populated (the `.empty`/`makeSnapshot`
  /// paths leave most optionals nil), so a dropped CodingKey or optionality
  /// change on any of them is detectable on a round-trip.
  private func makeFullyPopulatedSnapshot() -> WidgetSnapshot {
    WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: true, title: "Rainforest", subtitle: "Rain, Birds",
        soundSystemIconNames: ["cloud.rain", "bird"],
        thumbnailKey: "preset_thumb_abc", activeToken: GlobalSettings.quickMixToken,
        accentColorName: "teal"),
      favorites: [
        WidgetFavorite(
          token: GlobalSettings.allSoundsToken, displayName: "All Blankie Sounds",
          systemIconName: "square.grid.2x2", thumbnailKey: nil, accentColorName: "blue",
          subtitle: "Ada")
      ],
      quickMixSounds: [
        WidgetQuickMixSound(
          fileName: "rain", displayName: "Rain", systemIconName: "cloud.rain", isSelected: true)
      ],
      pinnableItems: [
        WidgetFavorite(
          token: GlobalSettings.soloToken(forFileName: "rain"), displayName: "Rain",
          systemIconName: "cloud.rain", thumbnailKey: "preset_thumb_xyz",
          accentColorName: "orange", subtitle: "Nature")
      ],
      defaultAccentColorName: "purple"
    )
  }

  // MARK: - Round-trip / corrupt fallback

  @Test func snapshotEncodeDecodeRoundTrips() throws {
    let original = makeSnapshot(title: "Round Trip")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    #expect(decoded == original)
  }

  @Test func fullyPopulatedSnapshotRoundTrips() throws {
    let original = makeFullyPopulatedSnapshot()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    #expect(decoded == original)
  }

  @Test func currentReturnsEmptyOnCorruptData() {
    UserDefaults.shared.set(Data([0xFF, 0x00, 0xFF]), forKey: "widgetSnapshot")
    #expect(WidgetStateStore.current() == .empty)
  }

  /// Forward compatibility: a payload missing an optional field still decodes
  /// (the field comes back nil), so an older cached snapshot survives a schema
  /// that adds optional fields. Strip a key from the encoded JSON to simulate it.
  @Test func decodeSucceedsWhenOptionalFieldMissing() throws {
    let original = makeFullyPopulatedSnapshot()
    let data = try JSONEncoder().encode(original)
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "defaultAccentColorName")
    let stripped = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: stripped)
    var expected = original
    expected.defaultAccentColorName = nil
    #expect(decoded == expected)
  }

  // MARK: - Publish dedup

  /// An identical republish must skip the write. Prove it behaviorally: publish
  /// `a`, corrupt the stored default, publish `a` again — the second call must
  /// early-return, leaving the corruption in place, so `current()` is `.empty`.
  @Test func identicalPublishSkipsWrite() {
    let a = makeSnapshot(title: "A")
    let b = makeSnapshot(title: "B")
    // Ensure the last-published value is `b` (≠ a) so the following publish(a)
    // actually writes regardless of what earlier tests left behind.
    WidgetStateStore.publish(b)
    WidgetStateStore.publish(a)
    #expect(WidgetStateStore.current() == a)

    UserDefaults.shared.set(Data([0xFF, 0x00]), forKey: "widgetSnapshot")
    WidgetStateStore.publish(a)
    #expect(WidgetStateStore.current() == .empty)
  }

  /// A changed snapshot writes through.
  @Test func changedPublishWritesThrough() {
    let a = makeSnapshot(title: "A")
    let b = makeSnapshot(title: "B")
    WidgetStateStore.publish(a)
    WidgetStateStore.publish(b)
    #expect(WidgetStateStore.current() == b)
  }

  // MARK: - Subtitle rule

  @Test func soundNameSummaryEmptyIsBlankie() {
    #expect(NowPlayingManager.soundNameSummary([]) == "Blankie")
  }

  @Test func soundNameSummarySingleLongTitleReturnedInFull() {
    let long = String(repeating: "x", count: 80)
    #expect(NowPlayingManager.soundNameSummary([long]) == long)
  }

  @Test func soundNameSummaryShortListJoined() {
    #expect(NowPlayingManager.soundNameSummary(["Rain", "Waves"]) == "Rain, Waves")
  }

  @Test func soundNameSummaryOverBudgetFallsBackToCount() {
    let titles = ["Rolling Thunder", "Distant Rainfall", "Crackling Fireplace", "Ocean Waves"]
    let summary = NowPlayingManager.soundNameSummary(titles)
    #expect(summary == String(localized: "\(titles.count) sounds"))
  }

  /// Boundary: a joined length of exactly the 50-char budget stays joined.
  @Test func soundNameSummaryExactlyAtBudgetJoined() {
    // "aaaa..." (24) + ", " (2) + "aaaa..." (24) = 50 characters joined.
    let part = String(repeating: "a", count: 24)
    let titles = [part, part]
    let joined = titles.joined(separator: ", ")
    #expect(joined.count == 50)
    #expect(NowPlayingManager.soundNameSummary(titles) == joined)
  }

  // MARK: - Freshness

  /// Setting the starred list republishes the catalog immediately, so the
  /// widget snapshot's favorites reflect the new list without any playback event.
  @Test func setStarredItemsRepublishesFavorites() {
    let tokens = [GlobalSettings.allSoundsToken, GlobalSettings.quickMixToken]
    // First set an empty list, then the target, so the target snapshot differs
    // from the last publish and is guaranteed to write.
    settings.setStarredItems([])
    settings.setStarredItems(tokens)
    #expect(WidgetStateStore.current().favorites.map(\.token) == tokens)
  }
}
