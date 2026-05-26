//
//  SoundSheetMacOSLayout.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct SoundSheetMacOSLayout: View {
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
  let hasChanges: Bool
  let title: LocalizedStringKey
  let buttonTitle: LocalizedStringKey
  let isDisabled: Bool
  let performAction: () -> Void
  let stopPreview: () -> Void
  let handleDismiss: () -> Void
  let dismiss: DismissAction

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Text(title)
          .font(.title2.bold())
      }
      .padding(.top, 32)
      .padding(.bottom, 18)

      Divider()

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

      Divider()

      HStack {
        if hasChanges {
          Button("Cancel") {
            handleDismiss()
            dismiss()
          }
          .buttonStyle(.bordered)
          .keyboardShortcut(.escape)

          Spacer()

          Button {
            performAction()
          } label: {
            Text(buttonTitle)
          }
          .buttonStyle(.borderedProminent)
          .disabled(isDisabled)
          .keyboardShortcut(.return)
        } else {
          Button("Done") {
            if isPreviewing {
              stopPreview()
            }
            dismiss()
          }
          .buttonStyle(.bordered)
          .keyboardShortcut(.escape)

          Spacer()
        }
      }
      .padding()
    }
    .frame(width: 480, height: sheetHeight)
  }

  /// Height sized to fit the grouped form so it doesn't scroll. macOS 14.6
  /// predates `.presentationSizing(.fitted)` and a `Form` won't self-size to
  /// content, so this is tuned per mode/content: custom sounds add a Delete
  /// row, and the volume slider only appears when Sound Check is off.
  private var sheetHeight: CGFloat {
    let base: CGFloat
    switch mode {
    case .add:
      base = 620
    case .edit(let sound):
      base = sound.isCustom ? 700 : 640
    }
    return base + (normalizeAudio ? 0 : 96)
  }
}
