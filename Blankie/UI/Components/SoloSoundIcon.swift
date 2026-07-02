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

struct SoloSoundIcon: View {
  let sound: Sound
  var iconSize: CGFloat = 200

  private let globalSettings = GlobalSettings.shared
  // Observe playback so the disc/icon/border react to play–pause; reading
  // AudioManager.shared statically misses updates (SoundIcon does the same).
  private let audioManager = AudioManager.shared

  private var accentColor: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  private var borderWidth: CGFloat { 6 }

  private var iconColor: Color {
    #if os(macOS)
      // Gray out while paused, matching the macOS grid tiles' iconColor.
      audioManager.isGloballyPlaying ? accentColor : .gray
    #else
      accentColor
    #endif
  }

  private var shouldShowProgressBorder: Bool {
    globalSettings.showProgressBorder && sound.isSelected
      && audioManager.isGloballyPlaying
  }

  var body: some View {
    ZStack {
      // Clear glass disc — interactive without heavy blur. (The paused state
      // still reads through iconColor's gray-out on macOS.)
      Circle()
        .fill(.clear)
        .frame(width: iconSize, height: iconSize)
        .glassEffect(.clear.interactive(), in: .circle)

      // Render as a font glyph, not .resizable: SF Symbols keep their built-in
      // optical centering this way (matching the grid/list/menu icons). With
      // .resizable, the raw vector bounds get scaled and some glyphs — e.g.
      // washer.fill's drum + basket — sit visibly off-center in the large disc.
      Image(systemName: sound.systemIconName)
        .font(.system(size: iconSize * 0.58))
        .foregroundColor(iconColor)

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
    .accessibilityLabel(Text(sound.localizedTitle))
    .accessibilityValue(Text(audioManager.isGloballyPlaying ? "Playing" : "Paused"))
    .accessibilityHint(Text("Plays or pauses the sound"))
    #if os(macOS)
      // macOS doesn't expose .onTapGesture as a VoiceOver activation; register
      // the toggle explicitly (matches SoundIcon's grid tiles).
      .accessibilityAction { audioManager.togglePlayback() }
    #endif
    .onTapGesture {
      // This icon only ever shows the soloed sound, so a tap toggles
      // playback rather than deselecting it.
      audioManager.togglePlayback()
    }
    .sensoryFeedback(.selection, trigger: sound.isSelected)
  }
}

/// The solo sound presented as a Now Playing card: the large icon with the
/// sound's name and its subtitle caption beneath, mirroring the system Now
/// Playing layout. In solo mode the mixer view itself IS the now-playing
/// surface, so this replaces the grid rather than living in a separate sheet.
struct SoloSoundCard: View {
  let sound: Sound

  var body: some View {
    VStack(spacing: 16) {
      SoloSoundIcon(sound: sound)

      VStack(spacing: 4) {
        Text(sound.localizedTitle)
          .font(.title2)
          .fontWeight(.semibold)

        if let subtitle = sound.localizedSubtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.center)
      // The name and caption are shown here on the card, so hide them from
      // VoiceOver — the icon already exposes the title as a button label.
      .accessibilityHidden(true)
    }
  }
}
