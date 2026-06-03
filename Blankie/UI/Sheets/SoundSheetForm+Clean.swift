//
//  SoundSheetForm+Clean.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct CleanSoundSheetForm: View {
  let mode: SoundSheetMode
  let isFilePreselected: Bool
  @Binding var soundName: String
  @Binding var selectedIcon: String
  @Binding var selectedFile: URL?
  @Binding var isImporting: Bool
  @Binding var randomizeStartPosition: Bool
  @Binding var normalizeAudio: Bool
  @Binding var volumeAdjustment: Float
  @Binding var loopSound: Bool
  @Binding var isPreviewing: Bool
  @Binding var previewSound: Sound?
  @Binding var previewProgress: Double
  @Binding var showingDeleteConfirmation: Bool
  @Binding var showingResetConfirmation: Bool
  @Binding var isDisappearing: Bool

  @ObservedObject var globalSettings = GlobalSettings.shared
  @State var showingIconPicker = false
  #if os(macOS)
    @State var showingCreditsEditor = false
  #endif

  var body: some View {
    Form {
      // File selection (only for add mode)
      if case .add = mode {
        Section {
          SoundFileSelector(
            selectedFile: $selectedFile,
            soundName: $soundName,
            isImporting: $isImporting,
            hideChangeButton: isFilePreselected
          )
        }
      }

      // Basic Information
      basicInformationSection

      // Audio Processing (includes preview)
      audioProcessingSection

      // Credits (read-only)
      creditsSection

      // Technical Details (edit mode only)
      technicalDetailsSection

      // Actions Section (Reset/Delete)
      actionSection
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .sheet(isPresented: $showingIconPicker) {
      NavigationStack {
        IconPickerView(selectedIcon: $selectedIcon)
      }
    }
    #if os(macOS)
      .sheet(isPresented: $showingCreditsEditor) {
        if let sound = currentEditSound {
          NavigationStack {
            SoundCreditsEditorView(sound: sound)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showingCreditsEditor = false }
              }
            }
          }
          .frame(minWidth: 420, minHeight: 420)
        }
      }
    #endif
  }

  #if os(macOS)
    /// The sound whose credits editor to present (edit mode only).
    private var currentEditSound: Sound? {
      if case .edit(let sound) = mode { return sound }
      return nil
    }
  #endif
}
