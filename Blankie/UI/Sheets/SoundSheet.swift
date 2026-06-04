//
//  SoundSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 5/28/25.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SoundSheetMode {
  case add
  case edit(Sound)
}

struct SoundSheet: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) var modelContext

  let mode: SoundSheetMode

  @State var soundName: String = ""
  @State var selectedIcon: String = "waveform.circle"
  @State var selectedFile: URL?
  @State var isImporting = false
  @State var importError: Error?
  @State var showingError = false
  @State var isProcessing = false
  @State var randomizeStartPosition: Bool = true
  @State var normalizeAudio: Bool = true
  @State var volumeAdjustment: Float = 1.0
  @State var loopSound: Bool = true
  @State var isPreviewing: Bool = false
  @State var previewSound: Sound?
  @State var previewProgress: Double = 0
  @State var previewTimer: Timer?
  @State var previousSoloModeSound: Sound?
  @State var wasPreviewSoundPlaying: Bool = false
  @State var showingDeleteConfirmation: Bool = false
  @State var showingResetConfirmation: Bool = false
  @State var isDisappearing: Bool = false

  // Track initial values to detect changes
  @State var initialSoundName: String = ""
  @State var initialSelectedIcon: String = ""
  @State var initialRandomizeStartPosition: Bool = true
  @State var initialNormalizeAudio: Bool = true
  @State var initialVolumeAdjustment: Float = 1.0
  @State var initialLoopSound: Bool = true

  let isFilePreselected: Bool
  let embedInNavigation: Bool

  init(mode: SoundSheetMode, preselectedFile: URL? = nil, embedInNavigation: Bool = true) {
    isFilePreselected = preselectedFile != nil
    self.embedInNavigation = embedInNavigation
    self.mode = mode

    switch mode {
    case .add:
      let values = Self.createAddModeInitValues(preselectedFile: preselectedFile)
      _soundName = State(initialValue: values.soundName)
      _selectedIcon = State(initialValue: values.selectedIcon)
      _selectedFile = State(initialValue: values.selectedFile)
      _initialSoundName = State(initialValue: values.initialSoundName)
      _initialSelectedIcon = State(initialValue: values.initialSelectedIcon)

    case .edit(let sound):
      let values = Self.createEditModeInitValues(sound: sound)
      _soundName = State(initialValue: values.soundName)
      _selectedIcon = State(initialValue: values.selectedIcon)
      _randomizeStartPosition = State(initialValue: values.randomizeStartPosition)
      _normalizeAudio = State(initialValue: values.normalizeAudio)
      _volumeAdjustment = State(initialValue: values.volumeAdjustment)
      _loopSound = State(initialValue: values.loopSound)
      _initialSoundName = State(initialValue: values.initialSoundName)
      _initialSelectedIcon = State(initialValue: values.initialSelectedIcon)
      _initialRandomizeStartPosition = State(
        initialValue: values.initialRandomizeStartPosition)
      _initialNormalizeAudio = State(initialValue: values.initialNormalizeAudio)
      _initialVolumeAdjustment = State(initialValue: values.initialVolumeAdjustment)
      _initialLoopSound = State(initialValue: values.initialLoopSound)
    }
  }

  var body: some View {
    baseContent
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: allowedContentTypes,
        allowsMultipleSelection: false
      ) { result in
        handleFileImport(result: result)
      }
      .alert(
        Text("Import Error"),
        isPresented: $showingError,
        presenting: importError
      ) { _ in
        Button("OK", role: .cancel) {}
      } message: { error in
        Text(error.localizedDescription)
      }
      .alert(
        Text("Delete Sound"),
        isPresented: $showingDeleteConfirmation
      ) {
        Button("Delete", role: .destructive) {
          deleteSound()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Are you sure you want to delete this sound? This action cannot be undone."
        )
      }
      .alert(
        Text("Reset to Defaults"),
        isPresented: $showingResetConfirmation
      ) {
        Button("Reset", role: .destructive) {
          if case .edit(let sound) = mode {
            handleResetToDefaults(for: sound)
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Are you sure you want to reset all customizations for this sound?"
        )
      }
      .overlay(alignment: .center) {
        if isProcessing {
          processingOverlay
        }
      }
      .modifier(
        SoundSheetChangeHandlers(
          isPreviewing: $isPreviewing,
          normalizeAudio: $normalizeAudio,
          volumeAdjustment: $volumeAdjustment,
          randomizeStartPosition: $randomizeStartPosition,
          loopSound: $loopSound,
          soundName: $soundName,
          selectedIcon: $selectedIcon,
          startPreview: startPreview,
          stopPreview: stopPreview,
          updateSoundSettings: updateSoundSettings
        )
      )
      .onAppear {
        handleOnAppear()
      }
      .onDisappear {
        handleOnDisappear()
      }
      // Tint the whole sheet so accent-colored icons (selected sound icon,
      // icon-picker highlight, Reset button) resolve from one stable environment
      // and don't flip when a tinted control is touched. Sound editing is
      // app-global (no preset), so use the app accent.
      .tint(GlobalSettings.shared.customAccentColor ?? .accentColor)
  }

  private var baseContent: some View {
    Group {
      #if os(macOS)
        macOSLayout
      #else
        iOSLayout
      #endif
    }
  }

  private var allowedContentTypes: [UTType] {
    [
      UTType.audio,
      UTType.mp3,
      UTType.wav,
      UTType.mpeg4Audio,
    ]
  }

  private func handleOnAppear() {
    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    debugLog("SoundSheet: handleOnAppear called for '\(soundName)'", .ui)

    if case .edit(let sound) = mode, sound.channelCount == nil {
      sound.loadSound()
    }
  }

  private func handleOnDisappear() {
    // Mark that we're disappearing to prevent re-entrance
    guard !isDisappearing else {
      debugLog("SoundSheet: handleOnDisappear called but already disappearing", .ui)
      return
    }

    let soundName = builtInSound?.title ?? sound?.title ?? "Unknown"
    debugLog(
      "SoundSheet: handleOnDisappear called for '\(soundName)', isPreviewing: \(isPreviewing)", .ui)
    isDisappearing = true

    if isPreviewing {
      debugLog("SoundSheet: Stopping preview in onDisappear", .ui)
      stopPreview()
    }
  }
}

extension SoundSheetMode {
  var isAdd: Bool {
    if case .add = self {
      return true
    }
    return false
  }
}

#Preview("Add Mode") {
  SoundSheet(mode: .add)
}
