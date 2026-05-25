//
//  AudioManager+MediaControls.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import MediaPlayer
import SwiftUI

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
        // Skip if in solo mode or quick mix
        guard self.soloModeSound == nil && !self.isQuickMix else {
          debugLog("🎵 AudioManager: Skipping next preset - in solo mode or quick mix")
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
        // Skip if in solo mode or quick mix
        guard self.soloModeSound == nil && !self.isQuickMix else {
          debugLog("🎵 AudioManager: Skipping previous preset - in solo mode or quick mix")
          return
        }

        self.navigateToPreviousPreset()
      }
      return .success
    }
  }

  @MainActor
  private func navigateToNextPreset() {
    let allPresets = PresetManager.shared.presets
    guard !allPresets.isEmpty else { return }

    // Filter out default preset if custom presets exist and sort by order
    let customPresets =
      allPresets
      .filter { !$0.isDefault }
      .sorted {
        let order1 = $0.order ?? Int.max
        let order2 = $1.order ?? Int.max
        return order1 < order2
      }
    let presets = customPresets.isEmpty ? allPresets : customPresets

    guard !presets.isEmpty else { return }

    let currentPresetId = PresetManager.shared.currentPreset?.id

    // Find current preset index in filtered list
    if let currentId = currentPresetId,
      let currentIndex = presets.firstIndex(where: { $0.id == currentId })
    {
      // Go to next preset, wrapping around
      let nextIndex = (currentIndex + 1) % presets.count
      let nextPreset = presets[nextIndex]

      debugLog("🎵 AudioManager: Switching to next preset: \(nextPreset.name)")
      do {
        try PresetManager.shared.applyPreset(nextPreset)
        // Ensure playback continues if it was playing
        if isGloballyPlaying {
          setGlobalPlaybackState(true)
        }
      } catch {
        debugLog("❌ AudioManager: Failed to apply next preset: \(error)")
      }
    } else {
      // No current preset or current is default when customs exist, go to first
      if let firstPreset = presets.first {
        debugLog("🎵 AudioManager: Switching to first preset: \(firstPreset.name)")
        do {
          try PresetManager.shared.applyPreset(firstPreset)
          if isGloballyPlaying {
            setGlobalPlaybackState(true)
          }
        } catch {
          debugLog("❌ AudioManager: Failed to apply first preset: \(error)")
        }
      }
    }
  }

  @MainActor
  private func navigateToPreviousPreset() {
    let allPresets = PresetManager.shared.presets
    guard !allPresets.isEmpty else { return }

    // Filter out default preset if custom presets exist and sort by order
    let customPresets =
      allPresets
      .filter { !$0.isDefault }
      .sorted {
        let order1 = $0.order ?? Int.max
        let order2 = $1.order ?? Int.max
        return order1 < order2
      }
    let presets = customPresets.isEmpty ? allPresets : customPresets

    guard !presets.isEmpty else { return }

    let currentPresetId = PresetManager.shared.currentPreset?.id

    // Find current preset index in filtered list
    if let currentId = currentPresetId,
      let currentIndex = presets.firstIndex(where: { $0.id == currentId })
    {
      // Go to previous preset, wrapping around
      let previousIndex = currentIndex > 0 ? currentIndex - 1 : presets.count - 1
      let previousPreset = presets[previousIndex]

      debugLog("🎵 AudioManager: Switching to previous preset: \(previousPreset.name)")
      do {
        try PresetManager.shared.applyPreset(previousPreset)
        // Ensure playback continues if it was playing
        if isGloballyPlaying {
          setGlobalPlaybackState(true)
        }
      } catch {
        debugLog("❌ AudioManager: Failed to apply previous preset: \(error)")
      }
    } else {
      // No current preset or current is default when customs exist, go to last
      if let lastPreset = presets.last {
        debugLog("🎵 AudioManager: Switching to last preset: \(lastPreset.name)")
        do {
          try PresetManager.shared.applyPreset(lastPreset)
          if isGloballyPlaying {
            setGlobalPlaybackState(true)
          }
        } catch {
          debugLog("❌ AudioManager: Failed to apply last preset: \(error)")
        }
      }
    }
  }

  /// Update next/previous command availability based on current mode
  func updateNextPreviousCommandState() {
    let commandCenter = MPRemoteCommandCenter.shared()
    let enableNextPrev = soloModeSound == nil && !isQuickMix

    commandCenter.nextTrackCommand.isEnabled = enableNextPrev
    commandCenter.previousTrackCommand.isEnabled = enableNextPrev

    debugLog("🎵 AudioManager: Next/Previous commands \(enableNextPrev ? "enabled" : "disabled")")
  }
}
