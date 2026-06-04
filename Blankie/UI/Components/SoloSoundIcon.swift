//
//  SoloSoundIcon.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//
//  The single large icon shown while solo mode is active. It is intentionally
//  not draggable and has no context menu — reordering and per-sound actions
//  live in the regular grid (`SoundGridView` / `GridSoundButton`). Tapping it
//  toggles global playback; solo is left by choosing another sound or preset.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct SoloSoundIcon: View {
    @ObservedObject var sound: Sound
    var iconSize: CGFloat = 200

    @ObservedObject private var globalSettings = GlobalSettings.shared

    private var accentColor: Color {
      globalSettings.customAccentColor ?? .accentColor
    }

    private var borderWidth: CGFloat { 6 }

    private var shouldShowProgressBorder: Bool {
      globalSettings.showProgressBorder && sound.isSelected
        && AudioManager.shared.isGloballyPlaying
    }

    var body: some View {
      ZStack {
        // Clear glass disc — interactive without heavy blur.
        Circle()
          .fill(.clear)
          .frame(width: iconSize, height: iconSize)
          .glassEffect(.clear.interactive(), in: .circle)

        Image(systemName: sound.systemIconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: iconSize * 0.64, height: iconSize * 0.64)
          .foregroundColor(accentColor)

        if shouldShowProgressBorder {
          let borderSize = iconSize - borderWidth

          Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: borderWidth)
            .frame(width: borderSize, height: borderSize)

          ProgressBorderView(
            iconSize: borderSize,
            borderWidth: borderWidth,
            sound: sound,
            color: accentColor
          )
        }
      }
      .frame(width: iconSize, height: iconSize)
      .contentShape(Circle())
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
      .accessibilityValue(Text(AudioManager.shared.isGloballyPlaying ? "Playing" : "Paused"))
      .accessibilityHint(Text("Plays or pauses the sound"))
      .onTapGesture {
        // This icon only ever shows the soloed sound, so a tap toggles
        // playback rather than deselecting it.
        AudioManager.shared.togglePlayback()
      }
      .sensoryFeedback(.selection, trigger: sound.isSelected)
    }
  }
#endif
