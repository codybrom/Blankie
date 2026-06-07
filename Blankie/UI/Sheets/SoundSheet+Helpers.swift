//
//  SoundSheet+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helper Properties
extension SoundSheet {

  var sound: Sound? {
    switch mode {
    case .add:
      return nil
    case .edit(let sound):
      return sound
    }
  }

  var builtInSound: Sound? {
    return sound
  }

  var title: LocalizedStringKey {
    switch mode {
    case .add:
      return "Import Sound"
    case .edit:
      return "Edit Sound"
    }
  }

  var buttonTitle: LocalizedStringKey {
    switch mode {
    case .add:
      return "Import Sound"
    case .edit:
      return ""  // No save button in edit mode
    }
  }

  var progressMessage: LocalizedStringKey {
    switch mode {
    case .add:
      return "Importing sound..."
    case .edit:
      return "Saving changes..."
    }
  }

  var isDisabled: Bool {
    let nameTrimmed = soundName.trimmingCharacters(in: .whitespacesAndNewlines)
    switch mode {
    case .add:
      return selectedFile == nil || nameTrimmed.isEmpty || isProcessing
    case .edit:
      return false  // Edit mode changes are instant, no disable needed
    }
  }

  var processingOverlay: some View {
    SoundSheetProcessingOverlay(progressMessage: progressMessage)
  }

  var isCustomSoundInEditMode: Bool {
    switch mode {
    case .edit(let sound):
      return sound.isCustom
    default:
      return false
    }
  }

  func handleResetToDefaults(for sound: Sound) {
    // Reset all values to defaults
    soundName = sound.originalTitle
    selectedIcon = sound.originalSystemIconName
    randomizeStartPosition = true
    normalizeAudio = true
    volumeAdjustment = 1.0
    loopSound = true
    fadeSound = true
    isPresetUseOnly = false
  }
}
