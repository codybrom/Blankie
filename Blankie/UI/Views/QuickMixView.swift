//
//  QuickMixView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct QuickMixView: View {
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared

    private var quickMixSounds: [Sound] {
      return globalSettings.quickMixSoundFileNames.compactMap { fileName in
        audioManager.sounds.first { $0.fileName == fileName && !$0.isCustom }
      }
    }

    var body: some View {
      ZStack {
        // Shared accent surface — same gradient used by the main grid so
        // Quick Mix reads as a variant of the same visual system.
        SoundSurfaceBackground(
          accent: globalSettings.customAccentColor ?? .accentColor
        )

        ScrollView {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16
          ) {
            ForEach(quickMixSounds, id: \.id) { sound in
              GridSoundButton(
                sound: sound,
                isActive: audioManager.isQuickMix && sound.isSelected,
                onTap: {
                  if !audioManager.isQuickMix {
                    audioManager.enterQuickMix()
                  }
                  audioManager.toggleQuickMixSound(sound)
                }
              )
            }
          }
          .padding()
        }
      }
    }
  }

  #Preview {
    QuickMixView()
  }
#endif
