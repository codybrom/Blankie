//
//  VolumePopoverView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

#if os(macOS)
  struct VolumePopoverView: View {
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared

    var accentColor: Color {
      globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("All Sounds")
            .font(.caption)
          Slider(
            value: Binding(
              get: { globalSettings.volume },
              set: { globalSettings.setVolume($0) }
            ),
            in: 0...1
          )
          .frame(width: 200)
          .tint(accentColor)
          .accessibilityLabel(Text("All Sounds"))
          .accessibilityValue(
            Text(globalSettings.volume.formatted(.percent.precision(.fractionLength(0)))))
        }

        // Only show middle divider if there are active sounds
        if audioManager.sounds.contains(where: \.isSelected) {
          Divider()

          // Active sound sliders
          ForEach(audioManager.sounds.filter(\.isSelected)) { sound in
            VStack(alignment: .leading, spacing: 4) {
              Text(LocalizedStringKey(sound.title))
                .font(.caption)

              Slider(
                value: Binding(
                  get: { Double(sound.volume) },
                  set: { sound.volume = Float($0) }
                ), in: 0...1
              )
              .frame(width: 200)
              .tint(accentColor)
              .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
              .accessibilityValue(
                Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0)))))
            }
          }
        }

        Divider()

        // Reset button
        Button("Reset Sounds") {
          audioManager.resetSounds()
        }
        .font(.caption)
      }
      .padding()
    }
  }
#endif
