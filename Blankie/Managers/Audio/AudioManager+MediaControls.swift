//
//  AudioManager+MediaControls.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import SwiftUI
import os

/// A destination the lock-screen / CarPlay next & previous commands can cycle
/// to: a preset, or a favorited single sound.
private enum NavigableItem {
  case preset(Preset)
  case single(Sound)
}

// MARK: - Media Controls
extension AudioManager {
  func setupMediaControls() {
    Logger.audio.debug("AudioManager: Setting up media controls")

    nowPlayingManager.installRemoteCommands(makeRemoteCommandHandlers())
    updateNextPreviousCommandState()
  }

  /// What the Now Playing backend runs when a remote command arrives.
  private func makeRemoteCommandHandlers() -> RemoteCommandHandlers {
    RemoteCommandHandlers(
      play: { [weak self] in
        Logger.nowPlaying.debug("AudioManager: remote play received")
        if !(self?.isGloballyPlaying ?? false) {
          self?.setGlobalPlaybackState(true)
        }
      },
      pause: { [weak self] in
        Logger.nowPlaying.debug("AudioManager: remote pause received")
        // Remote pauses cut instantly (see Sound.remotePauseFadeDuration).
        if self?.isGloballyPlaying ?? false {
          self?.setGlobalPlaybackState(false, pauseFadeDuration: Sound.remotePauseFadeDuration)
        }
      },
      togglePlayPause: { [weak self] in
        Logger.nowPlaying.debug("AudioManager: remote toggle play/pause received")
        // Same instant remote pause as pauseCommand (ignored when resuming).
        self?.togglePlayback(pauseFadeDuration: Sound.remotePauseFadeDuration)
      },
      next: { [weak self] in
        Logger.nowPlaying.debug("AudioManager: remote next received")
        guard let self = self else { return false }

        // Quick Mix isn't in the favorites cycle, but favorited single sounds are.
        guard !self.isQuickMix else {
          Logger.audio.debug("AudioManager: Skipping next - in quick mix")
          return true
        }

        self.navigateToNextPreset()
        return true
      },
      previous: { [weak self] in
        Logger.nowPlaying.debug("AudioManager: remote previous received")
        guard let self = self else { return false }

        guard !self.isQuickMix else {
          Logger.audio.debug("AudioManager: Skipping previous - in quick mix")
          return true
        }

        self.navigateToPreviousPreset()
        return true
      }
    )
  }

  /// Favorited items, in saved order, that next and previous cycle through.
  private var navigableItems: [NavigableItem] {
    let presets = PresetManager.shared.presets
    return GlobalSettings.shared.starredItems.compactMap { token in
      switch PlayableItem(token: token) {
      case .single(let fileName):
        return sound(fileName: fileName).map { NavigableItem.single($0) }
      case .allSounds:
        return presets.first { $0.isDefault }.map { NavigableItem.preset($0) }
      case .quickMix:
        return nil
      case .preset(let id):
        return presets.first { $0.id == id }.map { NavigableItem.preset($0) }
      case nil:
        return nil
      }
    }
  }

  /// Index of the single sound, else the current preset, in `items`. Nil when it
  /// isn't favorited.
  private func currentNavigableIndex(in items: [NavigableItem]) -> Int? {
    if let single = singleSound {
      return items.firstIndex {
        if case .single(let sound) = $0 { return sound.id == single.id }
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
      // Leave single sound without resuming so the previous mix doesn't briefly play.
      if singleSound != nil {
        exitSingleSoundWithoutResuming()
      }
      Logger.audio.debug("AudioManager: Navigating to preset: \(preset.name)")
      do {
        // Keep the current play/pause state. applyPreset starts the new mix
        // itself. Playing here first would start the old one.
        let wasPlaying = isGloballyPlaying
        let started = try PresetManager.shared.applyPreset(preset, autoPlay: wasPlaying)
        if wasPlaying, !started {
          setGlobalPlaybackState(true)
        }
      } catch {
        Logger.audio.error(
          "AudioManager: Failed to apply preset \(preset.name): \(error, privacy: .public)"
        )
      }
    case .single(let sound):
      Logger.audio.debug("AudioManager: Navigating to single sound: \(sound.title)")
      // Keep the current play/pause state.
      enterSingleSound(for: sound, startPlaying: isGloballyPlaying)
    }
  }

  @MainActor
  func navigateToNextPreset() {
    let items = navigableItems
    guard !items.isEmpty else { return }
    // With no current item, start at the first.
    let nextIndex = currentNavigableIndex(in: items).map { ($0 + 1) % items.count } ?? 0
    apply(items[nextIndex])
  }

  @MainActor
  func navigateToPreviousPreset() {
    let items = navigableItems
    guard !items.isEmpty else { return }
    // With no current item, start at the last.
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

  /// Enables next/previous when there's somewhere to go: another favorite when the
  /// current item is one, otherwise any favorite. Always off in Quick Mix.
  func updateNextPreviousCommandState() {
    // Nil until launch installs the backend. `setupMediaControls()` recomputes this.
    nowPlayingManager?.setNavigationCommandsEnabled(canNavigateNextPrevious)
  }
}
