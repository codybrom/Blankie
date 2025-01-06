//
//  VolumePopoverView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

struct VolumePopoverView: View {
  @ObservedObject var audioManager = AudioManager.shared
  @ObservedObject var globalSettings = GlobalSettings.shared

  var accentColor: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  var body: some View {
    VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Global Volume")
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
      }

      // Only show middle divider if there are active sounds
      if audioManager.sounds.contains(where: \.isSelected) {
        Divider()

        // Active sound sliders
        ForEach(audioManager.sounds.filter(\.isSelected)) { sound in
          VStack(alignment: .leading, spacing: 4) {
            Text(sound.title)
              .font(.caption)

            Slider(
              value: Binding(
                get: { Double(sound.volume) },
                set: { sound.volume = Float($0) }
              ), in: 0...1
            )
            .frame(width: 200)
            .tint(accentColor)
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
