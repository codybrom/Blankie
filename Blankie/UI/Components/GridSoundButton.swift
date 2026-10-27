//
//  GridSoundButton.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//
//  Sound tile shared by the preset grid and Quick Mix.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct GridSoundButton: View {
    let sound: Sound
    let audioManager = AudioManager.shared
    let globalSettings = GlobalSettings.shared

    /// Quick Mix passes its own active state; the grid passes nil.
    private let isActiveOverride: Bool?
    var onTap: () -> Void

    /// Computed so `body` observes `sound.isSelected`; `init` doesn't re-run on a toggle.
    var isActive: Bool { isActiveOverride ?? sound.isSelected }

    private var isQuickMix: Bool { isActiveOverride != nil }

    /// The nightstand sizes tiles so exactly two rows fill its flat half.
    @Environment(\.soundTileHeight) private var tileHeight
    private var compact: Bool { tileHeight != nil }
    private var iconSize: CGFloat { compact ? 60 : 80 }

    init(
      sound: Sound,
      isActive: Bool? = nil,
      onTap: (() -> Void)? = nil
    ) {
      self.sound = sound
      self.isActiveOverride = isActive
      self.onTap = onTap ?? { AudioManager.shared.toggleOrResume(sound) }
    }

    // Deliberately doesn't observe PresetManager, which republishes on every
    // sound-state save. The parent re-renders on preset changes.
    private var accentColor: Color {
      PresetManager.shared.themingPreset?.accentColor ?? globalSettings.customAccentColor
        ?? .accentColor
    }

    /// Lit only while selected and playing, so paused tiles read as paused.
    private var isLit: Bool {
      isActive && audioManager.isGloballyPlaying
    }

    private var shouldShowProgressBorder: Bool {
      globalSettings.showProgressBorder && isLit
    }

    var body: some View {
      // One container so the icon glass samples the background, not the card's
      // glass (glass on glass reads opaque at this size).
      GlassEffectContainer(spacing: 0) {
        VStack(spacing: compact ? 8 : 12) {
          VStack(spacing: compact ? 8 : 12) {
            iconView

            if globalSettings.showSoundNames {
              HStack(spacing: 4) {
                Text(sound.localizedTitle)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(.primary)
                  .multilineTextAlignment(.center)
                  // Nightstand tiles are fixed height, so names shrink to one line.
                  .lineLimit(compact ? 1 : 2)
                  .minimumScaleFactor(compact ? 0.5 : 1)

                if sound.isMusic {
                  MusicTagBadge(isActive: isLit, accentColor: accentColor)
                }
              }
              .accessibilityHidden(true)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .accessibilityElement(children: .ignore)
          .accessibilityAddTraits(.isButton)
          .accessibilityAddTraits(sound.isSelected ? [.isSelected] : [])
          // Explicit label for when "Show Sound Names" hides the title.
          .accessibilityLabel(Text(sound.localizedTitle))
          .onTapGesture {
            onTap()
          }
          // Reorder from the icon and title only, so the slider never starts a move.
          .reorderHandle()

          if !isQuickMix {
            volumeSlider
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 16)
        .padding(.horizontal, 12)
        .frame(height: tileHeight)
        // .regular glass reads opaque at tile size. Clear glass needs a dim
        // layer beneath it for legibility (Apple's guidance).
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
        .background(Color.black.opacity(0.15), in: .rect(cornerRadius: 16))
        .overlay {
          RoundedRectangle(cornerRadius: 16)
            .strokeBorder(accentColor.opacity(isLit ? 0.5 : 0.2), lineWidth: 1)
        }
      }
      // Scale the inactive tile down; an active tile above 1.0 would overflow its cell.
      .scaleEffect(isLit ? 1.0 : 0.95)
      .animation(.easeInOut(duration: 0.15), value: isLit)
      // Keyed to selection: `isLit` includes play state and would fire for every
      // tile on play/pause.
      .sensoryFeedback(.selection, trigger: sound.isSelected)
      .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      .accessibilityShowsLargeContentViewer {
        Label(sound.localizedTitle, systemImage: sound.systemIconName)
      }
    }

    // MARK: - Icon

    private var iconView: some View {
      ZStack {
        if shouldShowProgressBorder {
          ProgressBorderView(
            iconSize: iconSize,
            borderWidth: 3,
            sound: sound,
            color: accentColor
          )
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }

        Image(systemName: sound.systemIconName)
          .font(.system(size: compact ? 26 : 32, weight: .medium))
          .foregroundColor(iconForegroundColor)
      }
      .frame(width: iconSize, height: iconSize)
      .glassEffect(
        isLit
          ? .regular.tint(accentColor.opacity(0.5)).interactive()
          : .regular.interactive(),
        in: .circle
      )
      .opacity(isActive ? 1.0 : 0.4)
    }

    private var iconForegroundColor: Color {
      isLit ? accentColor : .secondary
    }

    // MARK: - Volume Slider

    private var volumeSlider: some View {
      Slider(
        value: Binding(
          get: { Double(sound.volume) },
          set: { sound.volume = Float($0) }
        ),
        in: 0...1
      )
      .tint(isLit ? accentColor : .gray)
      .disabled(!isActive)
      .padding(.horizontal, 4)
      .accessibilityLabel(Text(sound.localizedTitle))
      .accessibilityValue(
        Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0))))
      )
    }

  }

  #if DEBUG
    struct GridSoundButton_Previews: PreviewProvider {
      static var previews: some View {
        let sound = Sound(
          title: "Rain",
          systemIconName: "cloud.rain",
          fileName: "rain",
          fileExtension: "m4a",
          defaultOrder: 1,
          lufs: nil,
          normalizationFactor: nil,
          truePeakdBTP: nil,
          needsLimiter: false,
          isCustom: false,
          fileURL: nil,
          dateAdded: nil,
          customSoundDataID: nil
        )

        GridSoundButton(sound: sound)
          .frame(width: 180)
          .padding()
      }
    }
  #endif

  extension EnvironmentValues {
    /// Fixed tile height (with tighter spacing) for the nightstand's two rows.
    @Entry var soundTileHeight: CGFloat? = nil
  }
#endif
