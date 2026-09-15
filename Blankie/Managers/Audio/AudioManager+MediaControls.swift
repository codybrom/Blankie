//
//  AudioManager+MediaControls.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import SwiftUI
import os

/// A destination the lock-screen / CarPlay next & previous commands can cycle
/// to: a preset, or a favorited solo sound.
private enum NavigableItem {
  case preset(Preset)
  case solo(Sound)
}

// MARK: - Media Controls
extension AudioManager {
  func setupMediaControls() {
    Logger.audio.debug("AudioManager: Setting up media controls")

    nowPlayingManager.installRemoteCommands(makeRemoteCommandHandlers())

    // Enable next/previous only when not in solo mode or quick mix
    updateNextPreviousCommandState()
  }

  /// What the Now Playing backend runs when a remote command arrives.
  private func makeRemoteCommandHandlers() -> RemoteCommandHandlers {
    RemoteCommandHandlers(
      play: { [weak self] in
        // Only play if we're currently paused
        if !(self?.isGloballyPlaying ?? false) {
          self?.setGlobalPlaybackState(true)
        }
      },
      pause: { [weak self] in
        // Only pause if we're currently playing; remote pauses cut instantly
        // (see Sound.remotePauseFadeDuration).
        if self?.isGloballyPlaying ?? false {
          self?.setGlobalPlaybackState(false, pauseFadeDuration: Sound.remotePauseFadeDuration)
        }
      },
      togglePlayPause: { [weak self] in
        // Same instant remote pause as pauseCommand (ignored when resuming).
        self?.togglePlayback(pauseFadeDuration: Sound.remotePauseFadeDuration)
      },
      next: { [weak self] in
        guard let self = self else { return false }

        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          Logger.audio.debug("AudioManager: Skipping next - in quick mix")
          return true
        }

        self.navigateToNextPreset()
        return true
      },
      previous: { [weak self] in
        guard let self = self else { return false }

        // Quick Mix isn't part of the favorites cycle; solo sounds can be (when
        // favorited), so navigation handles solo itself.
        guard !self.isQuickMix else {
          Logger.audio.debug("AudioManager: Skipping previous - in quick mix")
          return true
        }

        self.navigateToPreviousPreset()
        return true
      }
    )
  }

  /// Destinations the lock-screen / CarPlay next & previous commands cycle
  /// through: exclusively favorited items in their saved order.
  private var navigableItems: [NavigableItem] {
    let presets = PresetManager.shared.presets
    return GlobalSettings.shared.starredItems.compactMap { token in
      switch PlayableItem(token: token) {
      case .solo(let fileName):
        return sound(fileName: fileName).map { NavigableItem.solo($0) }
      case .allSounds:
        return presets.first { $0.isDefault }.map { NavigableItem.preset($0) }
      case .quickMix:
        // Quick Mix isn't part of the favorites navigation cycle.
        return nil
      case .preset(let id):
        return presets.first { $0.id == id }.map { NavigableItem.preset($0) }
      case nil:
        return nil
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
      Logger.audio.debug("AudioManager: Navigating to preset: \(preset.name)")
      do {
        try PresetManager.shared.applyPreset(preset)
        if isGloballyPlaying {
          setGlobalPlaybackState(true)
        }
      } catch {
        Logger.audio.error(
          "AudioManager: Failed to apply preset \(preset.name): \(error, privacy: .public)"
        )
      }
    case .solo(let sound):
      Logger.audio.debug("AudioManager: Navigating to solo sound: \(sound.title)")
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
    // Optional-chained: before the launch bootstrap installs the backend there
    // is nothing to enable, and `setupMediaControls()` recomputes this the
    // moment it arrives.
    nowPlayingManager?.setNavigationCommandsEnabled(canNavigateNextPrevious)
  }
}
