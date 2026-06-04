//
//  SoundSheetChangeHandlers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct SoundSheetChangeHandlers: ViewModifier {
  @Binding var isPreviewing: Bool
  @Binding var normalizeAudio: Bool
  @Binding var volumeAdjustment: Float
  @Binding var randomizeStartPosition: Bool
  @Binding var loopSound: Bool
  @Binding var soundName: String
  @Binding var selectedIcon: String

  let startPreview: () -> Void
  let stopPreview: () -> Void
  let updateSoundSettings: () -> Void

  func body(content: Content) -> some View {
    content
      .onChange(of: isPreviewing) { _, previewing in
        debugLog("SoundSheetChangeHandlers: isPreviewing changed to: \(previewing)", .ui)
        if previewing {
          startPreview()
        } else {
          stopPreview()
        }
      }
      .onChange(of: normalizeAudio) { _, _ in
        updateSoundSettings()
      }
      .onChange(of: volumeAdjustment) { _, _ in
        updateSoundSettings()
      }
      .onChange(of: randomizeStartPosition) { _, _ in
        updateSoundSettings()
      }
      .onChange(of: loopSound) { _, _ in
        updateSoundSettings()
      }
      .onChange(of: soundName) { _, _ in
        updateSoundSettings()
      }
      .onChange(of: selectedIcon) { _, _ in
        updateSoundSettings()
      }
  }
}
