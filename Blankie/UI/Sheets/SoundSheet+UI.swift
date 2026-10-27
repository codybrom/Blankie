//
//  SoundSheet+UI.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

// MARK: - UI Components

extension SoundSheet {
  var macOSLayout: some View {
    SoundSheetMacOSLayout(
      mode: mode,
      isFilePreselected: isFilePreselected,
      soundName: $soundName,
      selectedIcon: $selectedIcon,
      selectedFile: $selectedFile,
      isImporting: $isImporting,
      convertToAACOnImport: $convertToAACOnImport,

      randomizeStartPosition: $randomizeStartPosition,
      normalizeAudio: $normalizeAudio,
      volumeAdjustment: $volumeAdjustment,
      loopSound: $loopSound,
      fadeSound: $fadeSound,
      isPresetUseOnly: $isPresetUseOnly,
      isMusic: $isMusic,
      addToPresetIDs: $addToPresetIDs,
      createMixPreset: $createMixPreset,
      isPreviewing: $isPreviewing,
      previewSound: $previewSound,
      previewProgress: $previewProgress,
      showingDeleteConfirmation: $showingDeleteConfirmation,
      showingResetConfirmation: $showingResetConfirmation,
      isDisappearing: $isDisappearing,
      hasChanges: hasChanges,
      title: title,
      buttonTitle: buttonTitle,
      isDisabled: isDisabled,
      performAction: performAction,
      stopPreview: stopPreview,
      handleDismiss: handleDismiss,
      dismiss: dismiss
    )
  }

  var iOSLayout: some View {
    Group {
      if embedInNavigation {
        NavigationStack {
          content
        }
      } else {
        content
      }
    }
  }

  var content: some View {
    SoundSheetForm(
      mode: mode,
      isFilePreselected: isFilePreselected,
      soundName: $soundName,
      selectedIcon: $selectedIcon,
      selectedFile: $selectedFile,
      isImporting: $isImporting,
      convertToAACOnImport: $convertToAACOnImport,

      randomizeStartPosition: $randomizeStartPosition,
      normalizeAudio: $normalizeAudio,
      volumeAdjustment: $volumeAdjustment,
      loopSound: $loopSound,
      fadeSound: $fadeSound,
      isPresetUseOnly: $isPresetUseOnly,
      isMusic: $isMusic,
      addToPresetIDs: $addToPresetIDs,
      createMixPreset: $createMixPreset,
      isPreviewing: $isPreviewing,
      previewSound: $previewSound,
      previewProgress: $previewProgress,
      showingDeleteConfirmation: $showingDeleteConfirmation,
      showingResetConfirmation: $showingResetConfirmation,
      isDisappearing: $isDisappearing
    )
    .navigationTitle(title)
    #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      // A modal editor roots its own NavigationStack and shows "Done". A pushed
      // editor (Edit Sound from Edit Preset) keeps the standard Back button.
      .navigationBarBackButtonHidden(embedInNavigation)
      .toolbar {
        if embedInNavigation {
          ToolbarItem(placement: .topBarLeading) {
            leadingNavigationButton.tint(Color.primary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          trailingNavigationButton.tint(Color.primary)
        }
      }
    #endif
  }

  @ViewBuilder
  var leadingNavigationButton: some View {
    switch mode {
    case .add:
      // Adding: this abandons the import (nothing is saved), so it's "Cancel"
      // beside the trailing Save.
      Button("Cancel", role: .cancel) {
        if isPreviewing {
          stopPreview()
        }
        dismiss()
      }
    case .edit:
      EmptyView()
    }
  }

  @ViewBuilder
  var trailingNavigationButton: some View {
    switch mode {
    case .add:
      if hasChanges {
        Button("Save") {
          performAction()
        }
        .disabled(isDisabled)
      }
    case .edit:
      // Edits apply live, so dismissing finishes ("Done"). Modal only; a pushed
      // editor keeps just its Back button.
      if embedInNavigation {
        Button("Done") {
          if isPreviewing {
            stopPreview()
          }
          dismiss()
        }
      }
    }
  }

  func handleFileImport(result: Result<[URL], Error>) {
    switch result {
    case .success(let files):
      if let file = files.first {
        selectedFile = file
        if soundName.isEmpty {
          Task {
            if let metadataTitle = await CustomSoundManager.shared.extractMetadataTitle(from: file)
            {
              soundName = metadataTitle
            } else {
              soundName = file.deletingPathExtension().lastPathComponent
            }
          }
        }
      }
    case .failure(let error):
      importError = error
      showingError = true
    }
  }
}
