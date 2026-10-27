//
//  SingleSoundIcon.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//
//  The large icon shown in single-sound mode. It has no drag or context menu, and a
//  tap toggles global playback.
//

import SwiftUI

struct SingleSoundIcon: View {
  let sound: Sound
  var iconSize: CGFloat = 200

  private let globalSettings = GlobalSettings.shared
  // Held as a property so the view observes playback; reading
  // AudioManager.shared statically misses updates.
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
      // Clear glass keeps the disc interactive without heavy blur.
      Circle()
        .fill(.clear)
        .frame(width: iconSize, height: iconSize)
        .glassEffect(.clear.interactive(), in: .circle)

      // A font glyph keeps SF Symbols' optical centering; .resizable scales the
      // raw vector bounds and pushes some glyphs (washer.fill) off-center.
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
      // macOS doesn't expose .onTapGesture as a VoiceOver activation.
      .accessibilityAction { audioManager.togglePlayback() }
    #endif
    .onTapGesture {
      // The icon only shows the single sound, so a tap toggles playback.
      audioManager.togglePlayback()
    }
    .sensoryFeedback(.selection, trigger: sound.isSelected)
  }
}

/// The single sound as a Now Playing card: the large icon with the name and
/// subtitle beneath. In single-sound mode it replaces the mixer's tiles.
struct SingleSoundCard: View {
  let sound: Sound
  var iconSize: CGFloat = 200

  var body: some View {
    VStack(spacing: 16) {
      SingleSoundIcon(sound: sound, iconSize: iconSize)
        // The text below carries the name and subtitle to VoiceOver, so the
        // icon is decorative here.
        .accessibilityHidden(true)

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
      // VoiceOver reads the name and subtitle as one announcement.
      .accessibilityElement(children: .combine)
    }
  }
}
