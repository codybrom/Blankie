//
//  GlobalSettingsFavoritesTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  The starred-items token list (feeds the iPad sidebar, CarPlay, and the
//  planned widget) and a couple of guard-railed setters. Pruning must keep the
//  special and solo tokens while dropping dead presets, or favorites silently
//  vanish or point at nothing.
//
//  Serialized + main-actor: mutates the GlobalSettings.shared singleton; each
//  test restores the touched in-memory values and UserDefaults keys.
//

import Foundation
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class GlobalSettingsFavoritesTests {
  private let settings = GlobalSettings.shared
  private let snapshot = DefaultsSnapshot([
    UserDefaultsKeys.starredItems,
    UserDefaultsKeys.menuBarOnlyMode,
    UserDefaultsKeys.hideDockWhenWindowClosed,
    UserDefaultsKeys.showMenuBarIcon,
  ])
  private let originalStarred: [String]
  private let originalMenuBarOnly: Bool
  private let originalHideDock: Bool
  private let originalShowMenuBar: Bool

  init() {
    originalStarred = settings.starredItems
    originalMenuBarOnly = settings.menuBarOnlyMode
    originalHideDock = settings.hideDockWhenWindowClosed
    originalShowMenuBar = settings.showMenuBarIcon
    settings.starredItems = []
  }

  deinit {
    settings.starredItems = originalStarred
    settings.menuBarOnlyMode = originalMenuBarOnly
    settings.hideDockWhenWindowClosed = originalHideDock
    settings.showMenuBarIcon = originalShowMenuBar
    snapshot.restore()
  }

  // MARK: - Token helpers

  @Test func soloTokenRoundTrips() {
    let token = GlobalSettings.soloToken(forFileName: "rain")
    #expect(token == "solo:rain")
    #expect(GlobalSettings.soloFileName(fromToken: token) == "rain")
    #expect(GlobalSettings.soloFileName(fromToken: GlobalSettings.allSoundsToken) == nil)
  }

  // MARK: - Starred list

  @Test func toggleAddsThenRemoves() {
    settings.toggleStarred(GlobalSettings.allSoundsToken)
    #expect(settings.isStarred(GlobalSettings.allSoundsToken))
    settings.toggleStarred(GlobalSettings.allSoundsToken)
    #expect(!settings.isStarred(GlobalSettings.allSoundsToken))
  }

  @Test func newlyStarredAppendInOrder() {
    settings.toggleStarred("a")
    settings.toggleStarred("b")
    settings.toggleStarred("c")
    #expect(settings.starredItems == ["a", "b", "c"])
  }

  @Test func setStarredPersistsToDefaults() {
    settings.setStarredItems(["x", "y"])
    #expect(settings.starredItems == ["x", "y"])
    #expect(UserDefaults.shared.stringArray(forKey: UserDefaultsKeys.starredItems) == ["x", "y"])
  }

  /// Prune drops tokens for deleted presets but keeps the special tokens and any
  /// solo token whose sound still exists.
  @Test func pruneDropsDeadPresetsKeepsSpecialAndLiveSolo() {
    let livePreset = UUID().uuidString
    let deadPreset = UUID().uuidString
    settings.setStarredItems([
      GlobalSettings.allSoundsToken, GlobalSettings.quickMixToken,
      livePreset, deadPreset, GlobalSettings.soloToken(forFileName: "rain"),
    ])

    settings.pruneStarredItems(
      validPresetIDs: [livePreset], validSoundFileNames: ["rain", "waves"])

    #expect(settings.starredItems.contains(GlobalSettings.allSoundsToken))
    #expect(settings.starredItems.contains(GlobalSettings.quickMixToken))
    #expect(settings.starredItems.contains(livePreset))
    #expect(settings.starredItems.contains(GlobalSettings.soloToken(forFileName: "rain")))
    #expect(!settings.starredItems.contains(deadPreset))
  }

  /// A solo token whose sound is gone is pruned when the sound list is known.
  @Test func pruneDropsSoloForMissingSound() {
    settings.setStarredItems([
      GlobalSettings.soloToken(forFileName: "rain"),
      GlobalSettings.soloToken(forFileName: "deleted"),
    ])
    settings.pruneStarredItems(validPresetIDs: [], validSoundFileNames: ["rain"])
    #expect(settings.starredItems == [GlobalSettings.soloToken(forFileName: "rain")])
  }

  /// When the caller doesn't know the sound list (nil), solo tokens are retained.
  @Test func pruneKeepsSoloWhenSoundsUnknown() {
    settings.setStarredItems([GlobalSettings.soloToken(forFileName: "anything"), UUID().uuidString])
    settings.pruneStarredItems(validPresetIDs: [], validSoundFileNames: nil)
    #expect(settings.starredItems == [GlobalSettings.soloToken(forFileName: "anything")])
  }

  // MARK: - Setters

  @Test func validateVolumeClamps() {
    #expect(settings.validateVolume(1.5) == 1.0)
    #expect(settings.validateVolume(-0.5) == 0.0)
    #expect(isClose(settings.validateVolume(0.42), 0.42))
  }

  /// Turning off the menu bar icon clears the Dock-hiding modes — the app can
  /// never hide both the Dock and the menu bar icon (no way back).
  @Test func disablingMenuBarIconClearsDockHiding() {
    settings.menuBarOnlyMode = true
    settings.hideDockWhenWindowClosed = true

    settings.setShowMenuBarIcon(false)

    #expect(!settings.showMenuBarIcon)
    #expect(!settings.menuBarOnlyMode)
    #expect(!settings.hideDockWhenWindowClosed)
  }
}
