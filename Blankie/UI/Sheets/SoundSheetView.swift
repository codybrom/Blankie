//
//  SoundSheetView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct SoundSheetView: View {
  let mode: SoundSheetMode
  let title: LocalizedStringKey
  let buttonTitle: LocalizedStringKey
  let isDisabled: Bool
  let performAction: () -> Void
  let dismiss: () -> Void

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

  var body: some View {
    #if os(macOS)
      VStack(spacing: 0) {
        // Header
        VStack(spacing: 8) {
          Text(title)
            .font(.title2.bold())
        }
        .padding(.top, 20)
        .padding(.bottom, 16)

        Divider()

        // Content
        SoundSheetForm(
          mode: mode,
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
          previewProgress: $previewProgress
        )

        Spacer()

        Divider()

        // Footer buttons
        HStack {
          Button("Cancel") {
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
        }
        .padding()
      }
      .frame(width: 450, height: mode.isAdd ? 720 : 700)
    #else
      NavigationView {
        SoundSheetForm(
          mode: mode,
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
          previewProgress: $previewProgress
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
          leading: Button("Cancel") {
            dismiss()
          },
          trailing: Button("Save") {
            performAction()
          }
          .disabled(isDisabled)
        )
      }
    #endif
  }
}
