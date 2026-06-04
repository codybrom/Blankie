//
//  SoundSheet+Preview.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI
import os

extension SoundSheet {
  // MARK: - Preview Methods

  internal func startPreview() {
    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    Logger.ui.debug(
      "SoundSheet: Starting preview for '\(soundName)' (isDisappearing: \(isDisappearing))")

    // Don't start preview if sheet is disappearing
    guard !isDisappearing else {
      Logger.ui.debug("SoundSheet: Skipping preview start - sheet is disappearing")
      return
    }

    Task { @MainActor in
      Logger.ui.debug("SoundSheet: Preview task started for '\(soundName)'")
      prepareForPreview()
      createPreviewSound()
      await startPreviewPlayback()
      startPreviewProgressTimer()
      Logger.ui.debug("SoundSheet: Preview started successfully for '\(soundName)'")
    }
  }

  private func startPreviewProgressTimer() {
    // Reset progress
    previewProgress = 0

    // Cancel any existing timer
    previewTimer?.invalidate()

    // Start a new timer to update progress
    previewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
      guard let preview = self.previewSound,
        let player = preview.player,
        player.isPlaying
      else {
        self.previewTimer?.invalidate()
        self.previewTimer = nil
        return
      }

      let duration = player.duration
      let currentTime = player.currentTime

      if duration > 0 {
        self.previewProgress = currentTime / duration
      }
    }
  }

  private func prepareForPreview() {
    // Save current solo mode sound if any (for restoration after preview)
    previousSoloModeSound = AudioManager.shared.soloModeSound

    // Exit any existing solo mode first (but don't change global playback state)
    if AudioManager.shared.soloModeSound != nil {
      AudioManager.shared.exitSoloModeWithoutResuming()
    }

    // Note: We don't change global playback state here since preview mode handles it
  }

  private func createPreviewSound() {
    switch mode {
    case .add:
      createAddPreview()

    case .edit(let sound):
      createEditPreview(sound)
    }
  }

  private func createAddPreview() {
    guard let fileURL = selectedFile else {
      isPreviewing = false
      return
    }

    // Reset this flag for add mode
    wasPreviewSoundPlaying = false

    // Create a temporary preview sound
    let fileName = fileURL.deletingPathExtension().lastPathComponent
    let preview = Sound(
      title: soundName.isEmpty ? fileName : soundName,
      systemIconName: selectedIcon,
      fileName: fileName,
      fileExtension: fileURL.pathExtension,
      lufs: nil,
      normalizationFactor: 1.0,
      isCustom: true,
      fileURL: fileURL,
      dateAdded: Date(),
      customSoundDataID: nil
    )

    // Set preview volume
    preview.volume = 1.0
    previewSound = preview
  }

  private func createEditPreview(_ sound: Sound) {
    // Track if this sound was playing before preview
    wasPreviewSoundPlaying = sound.player?.isPlaying == true && sound.isSelected

    // For edit mode, the preview sound is just the actual sound
    // Changes are already applied instantly, no need for temporary customization
    previewSound = sound
  }

  private func startPreviewPlayback() async {
    guard let preview = previewSound else { return }

    preview.loadSound()

    // Leave isSelected untouched during preview so the auto-play path never fires.
    AudioManager.shared.enterPreviewMode(for: preview)
  }

  internal func stopPreview() {
    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    Logger.ui.debug("SoundSheet: Stopping preview for '\(soundName)'")

    // Stop the progress timer
    previewTimer?.invalidate()
    previewTimer = nil
    previewProgress = 0

    Task { @MainActor in
      if let preview = previewSound {
        Logger.ui.debug("SoundSheet: Cleaning up preview sound '\(preview.title)'")

        // Exit preview mode (this restores all original states)
        AudioManager.shared.exitPreviewMode()

        if let previousSolo = previousSoloModeSound {
          Logger.ui.debug("SoundSheet: Restoring previous solo mode for '\(previousSolo.title)'")
          AudioManager.shared.enterSoloMode(for: previousSolo)
        }

        // Tear down add mode's temp player; edit mode previews the real Sound,
        // whose playback exitPreviewMode/enterSoloMode just restored.
        if case .add = mode {
          preview.player?.stop()
          preview.player = nil
        }
      }

      previewSound = nil
      previousSoloModeSound = nil
      wasPreviewSoundPlaying = false
    }
  }

  internal func updatePreviewVolume() {
    guard isPreviewing, let preview = previewSound else { return }

    Logger.ui.debug(
      "SoundSheet: Updating preview volume - normalize: \(normalizeAudio), adjustment: \(volumeAdjustment)"
    )

    Task { @MainActor in
      // Update the sound's volume based on the current customization
      preview.updateVolume()

      Logger.ui.debug("SoundSheet: Preview volume updated with current sheet settings")
    }
  }

}

// MARK: - Helper Extensions

extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}
