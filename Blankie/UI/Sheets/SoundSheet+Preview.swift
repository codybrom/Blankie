//
//  SoundSheet+Preview.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

extension SoundSheet {
  // MARK: - Preview Methods

  internal func startPreview() {
    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    debugLog(
      "🎵 SoundSheet: Starting preview for '\(soundName)' (isDisappearing: \(isDisappearing))")

    // Don't start preview if sheet is disappearing
    guard !isDisappearing else {
      debugLog("🎵 SoundSheet: Skipping preview start - sheet is disappearing")
      return
    }

    Task { @MainActor in
      debugLog("🎵 SoundSheet: Preview task started for '\(soundName)'")
      prepareForPreview()
      createPreviewSound()
      await startPreviewPlayback()
      startPreviewProgressTimer()
      debugLog("🎵 SoundSheet: Preview started successfully for '\(soundName)'")
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

    // Load the sound first
    preview.loadSound()

    // Note: We don't modify isSelected state during preview to avoid triggering auto-play logic

    // No need to apply temporary customization - changes are instant in edit mode

    // Enter preview mode (separate from solo mode)
    AudioManager.shared.enterPreviewMode(for: preview)
  }

  private func applyTemporaryCustomizationForPreview() {
    // No longer needed - changes are applied instantly in edit mode
    // For add mode, the preview sound is temporary and doesn't need persistent customization
  }

  internal func stopPreview() {
    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    debugLog("🎵 SoundSheet: Stopping preview for '\(soundName)'")

    // Stop the progress timer
    previewTimer?.invalidate()
    previewTimer = nil
    previewProgress = 0

    Task { @MainActor in
      if let preview = previewSound {
        debugLog("🎵 SoundSheet: Cleaning up preview sound '\(preview.title)'")

        // Exit preview mode (this restores all original states)
        AudioManager.shared.exitPreviewMode()

        // If we had a previous solo mode sound, restore it
        if let previousSolo = previousSoloModeSound {
          debugLog("🎵 SoundSheet: Restoring previous solo mode for '\(previousSolo.title)'")
          AudioManager.shared.enterSoloMode(for: previousSolo)
        }

        // Clean up preview sound for add/edit modes
        if case .add = mode {
          // For add mode, clean up the temporary preview sound
          preview.player?.stop()
          preview.player = nil
        } else if case .edit = mode {
          // For edit mode, clean up the temporary preview sound
          preview.player?.stop()
          preview.player = nil
        }
        // For edit mode with built-in sounds, the preview sound is the same as the original sound,
        // so we don't clean up the player in that case
      }

      previewSound = nil
      previousSoloModeSound = nil
      wasPreviewSoundPlaying = false
    }
  }

  internal func updatePreviewVolume() {
    guard isPreviewing, let preview = previewSound else { return }

    debugLog(
      "🎵 SoundSheet: Updating preview volume - normalize: \(normalizeAudio), adjustment: \(volumeAdjustment)"
    )

    Task { @MainActor in
      // Update the sound's volume based on the current customization
      preview.updateVolume()

      debugLog("🎵 SoundSheet: Preview volume updated with current sheet settings")
    }
  }

}

// MARK: - Helper Extensions

extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}
