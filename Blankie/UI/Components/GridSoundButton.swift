//
//  GridSoundButton.swift
//  Blankie
//
//  Unified sound tile used by both the normal preset grid and Quick Mix.
//  Visual style matches Quick Mix (white icon on accent background when
//  active) and adds an inline volume slider so users don't need a popover.
//  Callers pick `isActive` (grid uses sound.isSelected; Quick Mix uses
//  isQuickMix && sound.isSelected) and supply the tap behavior.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct GridSoundButton: View {
    @ObservedObject var sound: Sound
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared

    /// Explicit lit-state override. Quick Mix passes `isQuickMix &&
    /// sound.isSelected`; the grid passes `nil` and falls back to the sound's
    /// live selection below.
    private let isActiveOverride: Bool?
    /// Tap action. Grid mode toggles selection (or resumes playback); Quick
    /// Mix mode enters quick mix and toggles membership.
    var onTap: () -> Void

    /// Whether the tile should render as "lit up". Read live in `body` rather
    /// than captured in `init`: in the grid the tile observes `sound`, but its
    /// `init` doesn't re-run on a selection toggle (the parent isn't always
    /// re-evaluated — AudioManager only republishes when the *count* of
    /// selected sounds crosses 0↔1), so a stored copy would go stale and the
    /// tile wouldn't light up when tapped. Quick Mix supplies an explicit
    /// override, recomputed on each `QuickMixView` re-render.
    var isActive: Bool { isActiveOverride ?? sound.isSelected }

    init(
      sound: Sound,
      isActive: Bool? = nil,
      onTap: (() -> Void)? = nil
    ) {
      self._sound = ObservedObject(wrappedValue: sound)
      self.isActiveOverride = isActive
      self.onTap =
        onTap ?? {
          if !AudioManager.shared.isGloballyPlaying && sound.isSelected {
            AudioManager.shared.setGlobalPlaybackState(true)
          } else {
            sound.toggle()
          }
        }
    }

    private var accentColor: Color {
      globalSettings.customAccentColor ?? .accentColor
    }

    /// A tile only renders in its accent-lit form when the sound is selected
    /// AND Blankie is actually playing. When paused, selected tiles drop
    /// back to the dim/gray styling so the paused state reads clearly.
    private var isLit: Bool {
      isActive && audioManager.isGloballyPlaying
    }

    private var shouldShowProgressBorder: Bool {
      globalSettings.showProgressBorder && isLit
    }

    var body: some View {
      VStack(spacing: 12) {
        // Tap zone: everything above the slider.
        VStack(spacing: 12) {
          iconView

          if globalSettings.showSoundNames {
            Text(sound.title)
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.primary)
              .multilineTextAlignment(.center)
              .lineLimit(2)
          }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }

        volumeSlider
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .padding(.horizontal, 12)
      .glassEffect(
        isLit
          ? .regular.tint(accentColor.opacity(0.5)).interactive()
          : .regular.interactive(),
        in: .rect(cornerRadius: 16)
      )
      .scaleEffect(isLit ? 1.05 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: isLit)
      // Fire on the user's own selection toggle, not on `isLit`. Keying off
      // `isLit` (which folds in global play state) skipped feedback when
      // toggling while paused and fired one haptic per active tile on every
      // global play/pause.
      .sensoryFeedback(.selection, trigger: sound.isSelected)
    }

    // MARK: - Icon

    private var iconView: some View {
      ZStack {
        Circle()
          .fill(iconBackgroundColor)
          .frame(width: 80, height: 80)

        if shouldShowProgressBorder {
          ProgressBorderView(
            iconSize: 80,
            borderWidth: 3,
            sound: sound,
            color: accentColor
          )
          .allowsHitTesting(false)
        }

        Image(systemName: sound.systemIconName)
          .font(.system(size: 32, weight: .medium))
          .foregroundColor(iconForegroundColor)
      }
    }

    private var iconBackgroundColor: Color {
      if isLit {
        return accentColor.opacity(0.3)
      }
      return Color.secondary.opacity(0.2)
    }

    private var iconForegroundColor: Color {
      isLit ? .white : .secondary
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
      // Track the tile's active state, not raw selection: in Quick Mix a sound
      // selected by a prior preset would otherwise expose an enabled slider
      // that edits the base mix. In the grid `isActive == sound.isSelected`, so
      // this is unchanged there.
      .disabled(!isActive)
      .padding(.horizontal, 4)
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
#endif
