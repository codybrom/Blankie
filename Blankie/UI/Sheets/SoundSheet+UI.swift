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

      randomizeStartPosition: $randomizeStartPosition,
      normalizeAudio: $normalizeAudio,
      volumeAdjustment: $volumeAdjustment,
      loopSound: $loopSound,
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
    CleanSoundSheetForm(
      mode: mode,
      isFilePreselected: isFilePreselected,
      soundName: $soundName,
      selectedIcon: $selectedIcon,
      selectedFile: $selectedFile,
      isImporting: $isImporting,

      randomizeStartPosition: $randomizeStartPosition,
      normalizeAudio: $normalizeAudio,
      volumeAdjustment: $volumeAdjustment,
      loopSound: $loopSound,
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
      .navigationBarBackButtonHidden(true)
      .navigationBarItems(
        leading: leadingNavigationButton,
        trailing: trailingNavigationButton
      )
    #endif
  }

  @ViewBuilder
  var leadingNavigationButton: some View {
    Button("Done") {
      if isPreviewing {
        stopPreview()
      }
      dismiss()
    }
  }

  @ViewBuilder
  var trailingNavigationButton: some View {
    if hasChanges {
      Button("Save") {
        performAction()
      }
      .disabled(isDisabled)
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
