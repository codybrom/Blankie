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
    debugLog("AudioManager: Setting up media controls", .audio)

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
      debugLog("AudioManager: Media key play command received", .audio)
      Task { @MainActor in
        // Only play if we're currently paused
        if !(self?.isGloballyPlaying ?? false) {
          self?.setGlobalPlaybackState(true)
        }
      }
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      debugLog("AudioManager: Media key pause command received", .audio)
      Task { @MainActor in
        // Only pause if we're currently playing
        if self?.isGloballyPlaying ?? false {
          self?.setGlobalPlaybackState(false)
        }
      }
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      debugLog("AudioManager: Media key toggle command received", .audio)
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }
  }

  private func addNavigationCommandHandlers(_ commandCenter: MPRemoteCommandCenter) {
    // Next/Previous track commands for preset navigation
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      debugLog("AudioManager: Next track command received", .audio)
      guard let self = self else { return .commandFailed }

      Task { @MainActor in
        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          debugLog("AudioManager: Skipping next - in quick mix", .audio)
          return
        }

        self.navigateToNextPreset()
      }
      return .success
    }

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      debugLog("AudioManager: Previous track command received", .audio)
      guard let self = self else { return .commandFailed }

      Task { @MainActor in
        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          debugLog("AudioManager: Skipping previous - in quick mix", .audio)
          return
        }

        self.navigateToPreviousPreset()
      }
      return .success
    }
  }

  /// Destinations the lock-screen / CarPlay next & previous commands cycle
  /// through: exclusively favorited items in their saved order.
  private var navigableItems: [NavigableItem] {
    let presets = PresetManager.shared.presets
    return GlobalSettings.shared.starredItems.compactMap { token in
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
      debugLog("AudioManager: Navigating to preset: \(preset.name)", .audio)
      do {
        try PresetManager.shared.applyPreset(preset)
        if isGloballyPlaying {
          setGlobalPlaybackState(true)
        }
      } catch {
        logError("AudioManager: Failed to apply preset \(preset.name): \(error)", .audio)
      }
    case .solo(let sound):
      debugLog("AudioManager: Navigating to solo sound: \(sound.title)", .audio)
      // Respect the current play/pause state, matching preset navigation —
      // skipping onto a solo favorite while paused shouldn't start playback.
      enterSoloMode(for: sound, startPlaying: isGloballyPlaying)
    }
  }

  @MainActor
  func navigateToNextPreset() {
    let items = navigableItems
    guard !items.isEmpty else { return }
    // No locatable current item → start at the first.
    let nextIndex = currentNavigableIndex(in: items).map { ($0 + 1) % items.count } ?? 0
    apply(items[nextIndex])
  }

  @MainActor
  func navigateToPreviousPreset() {
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

  var canNavigateNextPrevious: Bool {
    let items = navigableItems
    let hasLocatableCurrent = currentNavigableIndex(in: items) != nil
    let canNavigate = hasLocatableCurrent ? items.count > 1 : !items.isEmpty
    return !isQuickMix && canNavigate
  }

  /// Update next/previous command availability. The cycle is favorites-only, so
  /// this is enabled when there's somewhere to go: with a locatable current item
  /// (a favorited preset, or in solo mode a favorited sound) we need more than
  /// one favorite; otherwise any favorite is a valid destination. Quick Mix is
  /// never part of the cycle.
  func updateNextPreviousCommandState() {
    let commandCenter = MPRemoteCommandCenter.shared()
    let enableNextPrev = canNavigateNextPrevious

    commandCenter.nextTrackCommand.isEnabled = enableNextPrev
    commandCenter.previousTrackCommand.isEnabled = enableNextPrev

    debugLog("AudioManager: Next/Previous commands \(enableNextPrev ? "enabled" : "disabled")", .audio)
  }
}
