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
  @Binding var convertToAACOnImport: Bool
  @Binding var randomizeStartPosition: Bool
  @Binding var normalizeAudio: Bool
  @Binding var volumeAdjustment: Float
  @Binding var loopSound: Bool
  @Binding var fadeSound: Bool
  @Binding var isPresetUseOnly: Bool
  @Binding var isMusic: Bool
  @Binding var addToPresetIDs: Set<UUID>
  @Binding var createMixPreset: Bool
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
          // macOS convention: the lone confirm/dismiss button sits bottom-right.
          Spacer()

          Button("Done") {
            if isPreviewing {
              stopPreview()
            }
            dismiss()
          }
          .buttonStyle(.bordered)
          .keyboardShortcut(.escape)
        }
      }
      .padding()
    }
    .frame(width: 480, height: sheetHeight)
  }

  private var sheetHeight: CGFloat {
    let base: CGFloat
    switch mode {
    case .add:
      base = 620
    case .edit(let sound):
      base = sound.isCustom ? 820 : 800
    }
    return base + (normalizeAudio ? 0 : 96)
  }
}
