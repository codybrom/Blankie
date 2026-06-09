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
        audioManager.sounds.first { $0.fileName == fileName && !$0.isCustom && !$0.isPresetUseOnly }
      }
    }

    var body: some View {
      ZStack {
        // Shared accent surface — same gradient used by the main grid so
        // Quick Mix reads as a variant of the same visual system.
        SoundSurfaceBackground(
          accent: globalSettings.customAccentColor ?? .accentColor
        )

        SoundGridView(
          sounds: quickMixSounds,
          onMove: { from, to in
            var ordered = quickMixSounds.map(\.fileName)
            ordered.move(fromOffsets: from, toOffset: to)
            // Carry over stored names that didn't resolve to a displayed sound
            // (e.g. a renamed built-in), so a reorder never prunes them.
            let shown = Set(ordered)
            ordered.append(
              contentsOf: globalSettings.quickMixSoundFileNames.filter { !shown.contains($0) })
            globalSettings.setQuickMixSoundFileNames(ordered)
          },
          tile: { sound in
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
        )
      }
    }
  }

  #Preview {
    QuickMixView()
  }
#endif
