//
//  GridSoundButton.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//
//  Unified sound tile used by both the normal preset grid and Quick Mix.
//  Visual style matches the list view: a translucent glass icon circle with
//  an accent-tinted symbol when active, dimmed when inactive, plus an inline
//  volume slider so users don't need a popover.
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

    /// Quick Mix is the only caller that passes an explicit `isActive` override
    /// (the grid passes nil). Use that to tell the two apart: Quick Mix is a
    /// membership picker — tap to add/remove — with no per-sound volume, so its
    /// tiles omit the slider entirely.
    private var isQuickMix: Bool { isActiveOverride != nil }

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

    // Prefer the theming preset's accent so tiles match the preset theme; fall
    // back to the app-wide custom accent, then the system accent. `themingPreset`
    // is nil during solo / Quick Mix, so those use the app accent. Read without
    // observing PresetManager (which republishes on every sound-state save) —
    // the grid's parent re-renders on preset changes, and this tile already
    // observes AudioManager, so solo / Quick Mix changes stay current too.
    private var accentColor: Color {
      PresetManager.shared.themingPreset?.accentColor ?? globalSettings.customAccentColor
        ?? .accentColor
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
      // Group the card glass and the icon's glass circle in one container so
      // both sample the gradient behind the tile as a unit, instead of the
      // icon glass sampling the already-frosted card glass beneath it. That
      // glass-on-glass double-frost — large at the icon's 80pt size — was what
      // made the tile read as opaque rather than glassy. (The list view avoids
      // it implicitly: its 50pt icon is a tiny fraction of a short, wide row.)
      GlassEffectContainer(spacing: 0) {
        VStack(spacing: 12) {
          VStack(spacing: 12) {
            iconView

            if globalSettings.showSoundNames {
              HStack(spacing: 4) {
                Text(LocalizedStringKey(sound.title))
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(.primary)
                  .multilineTextAlignment(.center)
                  .lineLimit(2)

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
          // Label the tile explicitly so VoiceOver/Voice Control name it even
          // when "Show Sound Names" hides the visible title (otherwise the only
          // accessible text is the SF Symbol's derived name).
          .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
          .onTapGesture {
            onTap()
          }
          // Reorder drags start from the icon/title only, never the slider
          // below — so adjusting volume can't be hijacked by the tile move.
          .reorderHandle()

          // Quick Mix is membership-only; per-sound volume lives in the grid.
          if !isQuickMix {
            volumeSlider
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        // Use the `.clear` glass variant, not `.regular`: regular Liquid Glass
        // frosts its backing heavily, so at the tile's size the surface read as
        // an opaque panel even though the rim still looked glassy. Clear glass
        // keeps the surface transparent so the background gradient shows
        // through. The lit/accent state is carried by the icon circle and
        // slider tint, not a tint on the whole tile.
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
        // Clear glass needs a dimming layer beneath it for legibility (Apple's
        // guidance): a slight neutral wash keeps the text and slider readable
        // over the brighter parts of the gradient without reintroducing the
        // frosted, opaque look.
        .background(Color.black.opacity(0.15), in: .rect(cornerRadius: 16))
        // Faint accent rim, a touch stronger when the tile is lit, so the edge
        // picks up the preset/accent color rather than a plain hairline.
        .overlay {
          RoundedRectangle(cornerRadius: 16)
            .strokeBorder(accentColor.opacity(isLit ? 0.5 : 0.2), lineWidth: 1)
        }
      }
      // Shrink the inactive tile rather than growing the active one: at the
      // grid's tile width an active tile scaled >1 overflows the 16pt spacing
      // and collides with its neighbor (most visible on iPad's wider tiles).
      // Keeping the active tile at 1.0 means it never exceeds its cell, so the
      // gap is always preserved.
      .scaleEffect(isLit ? 1.0 : 0.95)
      .animation(.easeInOut(duration: 0.15), value: isLit)
      // Fire on the user's own selection toggle, not on `isLit`. Keying off
      // `isLit` (which folds in global play state) skipped feedback when
      // toggling while paused and fired one haptic per active tile on every
      // global play/pause.
      .sensoryFeedback(.selection, trigger: sound.isSelected)
      .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      .accessibilityShowsLargeContentViewer {
        Label(LocalizedStringKey(sound.title), systemImage: sound.systemIconName)
      }
    }

    // MARK: - Icon

    private var iconView: some View {
      ZStack {
        if shouldShowProgressBorder {
          ProgressBorderView(
            iconSize: 80,
            borderWidth: 3,
            sound: sound,
            color: accentColor
          )
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }

        Image(systemName: sound.systemIconName)
          .font(.system(size: 32, weight: .medium))
          .foregroundColor(iconForegroundColor)
      }
      .frame(width: 80, height: 80)
      // Glass icon circle matching the list view: accent-tinted when lit,
      // plain glass otherwise. Inactive icons dim to read as "off".
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
      // Only rendered in the grid (Quick Mix omits it). Disable for sounds that
      // aren't selected so the slider can't edit an inactive sound.
      .disabled(!isActive)
      .padding(.horizontal, 4)
      .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
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
#endif
