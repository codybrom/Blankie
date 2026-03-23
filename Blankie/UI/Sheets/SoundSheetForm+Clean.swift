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

      // Actions Section (Reset/Delete)
      actionSection
    }
    .sheet(isPresented: $showingIconPicker) {
      NavigationStack {
        IconPickerView(selectedIcon: $selectedIcon)
      }
    }
    #if os(macOS)
      .frame(minHeight: 500)
    #endif
  }
}
