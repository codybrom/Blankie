//
//  SoundSheetForm.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct SoundSheetForm: View {
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

// MARK: - Color Helpers
extension SoundSheetForm {
  var textColorForCurrentTheme: Color {
    let color = globalSettings.customAccentColor ?? .accentColor
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }

  func textColorForAccentColor(_ accentColor: AccentColor) -> Color {
    guard let color = accentColor.color else { return .white }
    #if os(macOS)
      if let nsColor = NSColor(color).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      } else {
        return .white
      }
    #else
      return .white
    #endif
  }
}

// MARK: - Volume Helpers
extension SoundSheetForm {
  var volumePercentageText: String {
    let delta = Double(volumeAdjustment) - 1.0
    return delta.formatted(
      .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
  }
}

// MARK: - Preview Helpers
extension SoundSheetForm {
  func togglePreview() {
    isPreviewing.toggle()
  }

  func startPreview() {
    isPreviewing = true
  }

  func stopPreview() {
    isPreviewing = false
  }
}
