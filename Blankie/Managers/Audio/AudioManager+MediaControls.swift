//
//  AudioManager+MediaControls.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import MediaPlayer
import SwiftUI

/// A destination the lock-screen / CarPlay next & previous commands can cycle
/// to: a preset, or a favorited solo sound.
private enum NavigableItem {
  case preset(Preset)
  case solo(Sound)
}

// MARK: - Media Controls
extension AudioManager {
  func setupMediaControls() {
    debugLog("🎵 AudioManager: Setting up media controls")

    let commandCenter = MPRemoteCommandCenter.shared()
    configureMediaCommands(commandCenter)
    removeExistingCommandHandlers(commandCenter)
    addPlaybackCommandHandlers(commandCenter)
    addNavigationCommandHandlers(commandCenter)
  }

  private func configureMediaCommands(_ commandCenter: MPRemoteCommandCenter) {
    // Enable the commands
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true

    // Enable next/previous only when not in solo mode or quick mix
    updateNextPreviousCommandState()
  }

  private func removeExistingCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    // Remove all previous handlers
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
  }

  private func addPlaybackCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    commandCenter.playCommand.addTarget { [weak self] _ in
      debugLog("🎵 AudioManager: Media key play command received")
      Task { @MainActor in
        // Only play if we're currently paused
        if !(self?.isGloballyPlaying ?? false) {
          self?.setGlobalPlaybackState(true)
        }
      }
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      debugLog("🎵 AudioManager: Media key pause command received")
      Task { @MainActor in
        // Only pause if we're currently playing
        if self?.isGloballyPlaying ?? false {
          self?.setGlobalPlaybackState(false)
        }
      }
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      debugLog("🎵 AudioManager: Media key toggle command received")
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }
  }

  private func addNavigationCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    // Next/Previous track commands for preset navigation
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      debugLog("🎵 AudioManager: Next track command received")
      guard let self = self else { return .commandFailed }

      Task { @MainActor in
        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          debugLog("🎵 AudioManager: Skipping next - in quick mix")
          return
        }

        self.navigateToNextPreset()
      }
      return .success
    }

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      debugLog("🎵 AudioManager: Previous track command received")
      guard let self = self else { return .commandFailed }

      Task { @MainActor in
        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          debugLog("🎵 AudioManager: Skipping previous - in quick mix")
          return
        }

        self.navigateToPreviousPreset()
      }
      return .success
    }
  }

  /// Destinations the lock-screen / CarPlay next & previous commands cycle
  /// through: favorites in their saved order (Quick Mix is skipped — it has its
  /// own controls; favorited solo sounds are included), then every other custom
  /// preset by order. Falls back to the default preset when there's nothing
  /// else, so next/previous always re-applies something.
  private var navigableItems: [NavigableItem] {
    let presets = PresetManager.shared.presets
    let favorites: [NavigableItem] = GlobalSettings.shared.starredItems.compactMap { token in
      if GlobalSettings.soloFileName(fromToken: token) != nil {
        return sound(forSoloToken: token).map { NavigableItem.solo($0) }
      }
      switch token {
      case GlobalSettings.allSoundsToken:
        return presets.first { $0.isDefault }.map { NavigableItem.preset($0) }
      case GlobalSettings.quickMixToken:
        return nil
      default:
        return presets.first { $0.id.uuidString == token }.map { NavigableItem.preset($0) }
      }
    }
    let favoritePresetIDs = Set(
      favorites.compactMap { item -> UUID? in
        if case .preset(let preset) = item { return preset.id }
        return nil
      })
    // Only presets backfill the cycle — non-favorited solo sounds stay out of
    // next/previous (a favorited solo sound is already in `favorites`).
    let rest: [NavigableItem] =
      presets
      .filter { !$0.isDefault && !favoritePresetIDs.contains($0.id) }
      .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
      .map { NavigableItem.preset($0) }
    let result = favorites + rest
    if result.isEmpty, let defaultPreset = presets.first(where: { $0.isDefault }) {
      return [.preset(defaultPreset)]
    }
    return result
  }

  /// Index of the currently-playing destination within `items`: the soloed
  /// sound when in solo mode, otherwise the current preset. Nil when the active
  /// item isn't in the list (e.g. soloing a sound that isn't favorited).
  private func currentNavigableIndex(in items: [NavigableItem]) -> Int? {
    if let solo = soloModeSound {
      return items.firstIndex {
        if case .solo(let sound) = $0 { return sound.id == solo.id }
        return false
      }
    }
    if let currentID = PresetManager.shared.currentPreset?.id {
      return items.firstIndex {
        if case .preset(let preset) = $0 { return preset.id == currentID }
        return false
      }
    }
    return nil
  }

  @MainActor
  private func apply(_ item: NavigableItem) {
    switch item {
    case .preset(let preset):
      // Leave solo without resuming so the previous mix doesn't briefly play.
      if soloModeSound != nil {
        exitSoloModeWithoutResuming()
      }
      debugLog("🎵 AudioManager: Navigating to preset: \(preset.name)")
      do {
        try PresetManager.shared.applyPreset(preset)
        if isGloballyPlaying {
          setGlobalPlaybackState(true)
        }
      } catch {
        debugLog("❌ AudioManager: Failed to apply preset \(preset.name): \(error)")
      }
    case .solo(let sound):
      debugLog("🎵 AudioManager: Navigating to solo sound: \(sound.title)")
      // Respect the current play/pause state, matching preset navigation —
      // skipping onto a solo favorite while paused shouldn't start playback.
      enterSoloMode(for: sound, startPlaying: isGloballyPlaying)
    }
  }

  @MainActor
  private func navigateToNextPreset() {
    let items = navigableItems
    guard !items.isEmpty else { return }
    // No locatable current item → start at the first.
    let nextIndex = currentNavigableIndex(in: items).map { ($0 + 1) % items.count } ?? 0
    apply(items[nextIndex])
  }

  @MainActor
  private func navigateToPreviousPreset() {
    let items = navigableItems
    guard !items.isEmpty else { return }
    // No locatable current item → start at the last.
    let previousIndex: Int
    if let index = currentNavigableIndex(in: items) {
      previousIndex = index > 0 ? index - 1 : items.count - 1
    } else {
      previousIndex = items.count - 1
    }
    apply(items[previousIndex])
  }

  /// Update next/previous command availability. Enabled when there's more than
  /// one destination to cycle and the current one is locatable: in solo mode
  /// that means the soloed sound is favorited (otherwise it isn't in the list);
  /// Quick Mix is never part of the cycle.
  func updateNextPreviousCommandState() {
    let commandCenter = MPRemoteCommandCenter.shared()
    let items = navigableItems
    // Enable whenever there's somewhere to go. When the current item is in the
    // cycle (a favorite, or the current preset) we need more than one item to
    // move. When it isn't — a non-favorited solo sound, or the default preset —
    // any item is a valid destination: next starts at the top of favorites and
    // works through from there.
    let hasLocatableCurrent = currentNavigableIndex(in: items) != nil
    let canNavigate = hasLocatableCurrent ? items.count > 1 : !items.isEmpty
    let enableNextPrev = !isQuickMix && canNavigate

    commandCenter.nextTrackCommand.isEnabled = enableNextPrev
    commandCenter.previousTrackCommand.isEnabled = enableNextPrev

    debugLog("🎵 AudioManager: Next/Previous commands \(enableNextPrev ? "enabled" : "disabled")")
  }
}
