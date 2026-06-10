//
//  MenuBarContent.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/26.
//

#if os(macOS)
  import SwiftUI

  /// Popover content — a custom-header navigator (Library ← Mixer → Timer,
  /// opening on Mixer). A system `NavigationStack` wouldn't self-size in a
  /// `MenuBarExtra` window; the owned fixed-height header sizes to content.
  struct MenuBarContent: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var globalSettings = GlobalSettings.shared
    @ObservedObject private var presetManager = PresetManager.shared
    @ObservedObject private var timerManager = TimerManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// Screens ordered left-to-right, so the slide direction falls out of the
    /// raw value (a higher target slides in from the right).
    private enum Screen: Int { case library, mixer, timer }

    @State private var screen: Screen = .mixer
    @State private var forward = true

    private let popoverWidth: CGFloat = 340

    var body: some View {
      VStack(spacing: 0) {
        header
        Divider()
        screenContent
          .id(contentID)
          .transition(.push(from: forward ? .trailing : .leading))
      }
      .frame(width: popoverWidth)
    }

    /// Identity of the visible screen. The timer's active state is folded in so
    /// the popover re-sizes for the taller running layout instead of clipping.
    private var contentID: String {
      screen == .timer ? "timer-\(timerManager.isTimerActive)" : "\(screen)"
    }

    /// Animate to another screen, deriving the push direction from screen order.
    private func go(to newScreen: Screen) {
      forward = newScreen.rawValue > screen.rawValue
      withAnimation(.smooth(duration: 0.3)) { screen = newScreen }
    }

    // MARK: - Header

    /// A fixed-height bar so the title block centers the same on every screen.
    private var header: some View {
      HStack(spacing: 10) {
        leadingButton
        VStack(alignment: .leading, spacing: 1) {
          Text(headerTitle)
            .font(.headline)
            .lineLimit(1)
          if let subtitle = headerSubtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if screen != .timer {
          optionsMenu
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 56)
    }

    @ViewBuilder private var leadingButton: some View {
      switch screen {
      case .library:
        // Root — no back; actions live in the trailing "⋯" menu.
        EmptyView()
      case .mixer:
        circleButton("chevron.backward") { go(to: .library) }
          .accessibilityLabel(Text("Back"))
      case .timer:
        circleButton("chevron.backward") { go(to: .mixer) }
          .accessibilityLabel(Text("Back"))
      }
    }

    /// Trailing "⋯" menu — a menu-bar app's actions live in the click-through UI
    /// (no right-click menu). Hidden on the focused timer screen.
    private var optionsMenu: some View {
      Menu {
        Button("Open Blankie", action: openMainWindow)
        Button("Settings…", action: openSettings)
        Divider()
        Button("Quit Blankie") { NSApplication.shared.terminate(nil) }
      } label: {
        glassCircle("ellipsis")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel(Text("More Options"))
    }

    /// Glass circle for the back chevron / "⋯" menu.
    private func glassCircle(_ systemImage: String) -> some View {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .frame(width: 30, height: 30)
        .glassEffect(.regular.interactive(), in: .circle)
        .contentShape(Circle())
    }

    private func circleButton(
      _ systemImage: String, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) { glassCircle(systemImage) }
        .buttonStyle(.plain)
    }

    /// Opens the main window and closes the popover.
    private func openMainWindow() {
      openWindow(id: "main")
      NSApp.activate()
      dismiss()
    }

    private var headerTitle: String {
      switch screen {
      case .library: return String(localized: "Library")
      case .mixer: return mixerTitle
      case .timer: return String(localized: "Sleep Timer")
      }
    }

    /// Mixer subtitle: the static sleep-timer end time, matching the main window.
    private var headerSubtitle: String? {
      guard screen == .mixer, timerManager.isTimerActive,
        let endTime = timerManager.getEndTime()
      else { return nil }
      return String(localized: "Pausing at \(endTime.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - Screens

    @ViewBuilder private var screenContent: some View {
      switch screen {
      case .library:
        // Real library list; selecting a row moves to the mixer. The greedy
        // List needs a definite height.
        LibraryView(presentation: .menuBar, onSelection: { go(to: .mixer) })
          .frame(height: 460)
      case .mixer:
        mixerContent
      case .timer:
        // Claim the timer's full height (fixedSize) so a short preceding screen
        // (small preset / solo) can't squeeze the popover and clip it.
        // Start/cancel navigates back, not dismiss (which closes the popover).
        TimerView(onFinish: { go(to: .mixer) })
          .fixedSize(horizontal: false, vertical: true)
      }
    }

    /// The mixer: the solo icon or the iOS-style sound list, plus the control bar.
    private var mixerContent: some View {
      VStack(spacing: 0) {
        if let solo = audioManager.soloModeSound {
          SoloSoundIcon(sound: solo, iconSize: 120)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
          // Hug the rows' measured height up to a cap, then scroll.
          ScrollView {
            VStack(spacing: 0) {
              ForEach(filteredSounds) { sound in
                MenuBarSoundRow(
                  sound: sound,
                  accent: rowAccent,
                  isGloballyPlaying: audioManager.isGloballyPlaying,
                  showSoundNames: globalSettings.showSoundNames
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
              }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
              listContentHeight = height
            }
          }
          .frame(height: min(listContentHeight, maxListHeight))
          .scrollDisabled(listContentHeight <= maxListHeight)
        }

        Divider()

        controlBar
      }
    }

    // MARK: - Helpers

    /// Opens the main window's in-window Settings pane.
    private func openSettings() {
      AppState.shared.showingSettingsPane = true
      openWindow(id: "main")
      NSApp.activate()
      dismiss()
    }

    @State private var listContentHeight: CGFloat = 300
    private let maxListHeight: CGFloat = 420

    /// The sounds shown in the list, ordered. Shared with the main grid and iOS.
    private var filteredSounds: [Sound] {
      audioManager.orderedVisibleSounds(for: presetManager.currentPreset)
    }

    /// Mixer title: solo sound, Quick Mix, or the preset name.
    private var mixerTitle: String {
      if let solo = audioManager.soloModeSound {
        return String(localized: String.LocalizationValue(solo.title))
      }
      if audioManager.isQuickMix { return String(localized: "Quick Mix") }
      return presetManager.currentPreset?.displayName ?? "Blankie"
    }

    /// Active accent: a theming preset's color wins; app accent in solo/Quick Mix.
    private var activeAccent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    /// Accent for the sound rows: a custom preset's color, else the app accent.
    /// Resolved once here so each row only observes its own sound. (Distinct from
    /// `activeAccent`, which prefers the theming preset.)
    private var rowAccent: Color {
      if let preset = presetManager.currentPreset, !preset.isDefault,
        let presetColor = preset.accentColor
      {
        return presetColor
      }
      return globalSettings.customAccentColor ?? .accentColor
    }

    private var controlBar: some View {
      HStack(spacing: 12) {
        Button {
          audioManager.togglePlayback()
        } label: {
          Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            .frame(width: 18, height: 18)
            .foregroundStyle(activeAccent)
        }
        .buttonStyle(.borderless)
        .disabled(!audioManager.isGloballyPlaying && !audioManager.hasSelectedSounds)
        .help(audioManager.isGloballyPlaying ? "Pause" : "Play")
        .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))

        Image(systemName: "speaker.wave.2.fill")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Slider(
          value: Binding(
            get: { globalSettings.volume },
            set: { globalSettings.setVolume($0) }
          ),
          in: 0...1
        )
        .controlSize(.small)
        .tint(activeAccent)
        .accessibilityLabel(Text("All Sounds"))
        .accessibilityValue(
          Text(globalSettings.volume.formatted(.percent.precision(.fractionLength(0)))))

        // Sleep timer screen; tinted when active.
        Button {
          go(to: .timer)
        } label: {
          Image(systemName: "timer")
            .frame(width: 18, height: 18)
            .foregroundStyle(timerManager.isTimerActive ? activeAccent : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("Sleep Timer")
        .accessibilityLabel(Text("Sleep Timer"))
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
  }

  /// Compact list row mirroring iOS `SoundRowView` (glass icon + title + inline
  /// volume slider). Tap toggles the sound and starts playback if paused. The
  /// parent resolves the shared accent / playing / show-names values so each row
  /// only observes its own `sound`.
  private struct MenuBarSoundRow: View {
    @ObservedObject var sound: Sound
    let accent: Color
    let isGloballyPlaying: Bool
    let showSoundNames: Bool

    /// Toggle the sound, or — when paused and this sound is already selected —
    /// resume playback instead of deselecting it (matching the grid tile).
    private func activate() {
      if !AudioManager.shared.isGloballyPlaying && sound.isSelected {
        AudioManager.shared.setGlobalPlaybackState(true)
      } else {
        sound.toggle()
      }
    }

    var body: some View {
      HStack(spacing: 14) {
        Image(systemName: sound.systemIconName)
          .font(.system(size: 20))
          .foregroundStyle(
            !isGloballyPlaying ? Color.gray : (sound.isSelected ? accent : Color.gray)
          )
          .frame(width: 40, height: 40)
          .glassEffect(
            sound.isSelected && isGloballyPlaying
              ? .regular.tint(accent.opacity(0.5)).interactive()
              : .regular.interactive(),
            in: .circle
          )
          .opacity(sound.isSelected ? 1.0 : 0.4)
          // VoiceOver: macOS doesn't expose .onTapGesture as an activation, so
          // surface the toggle as a button on the icon (the slider is its own
          // adjustable stop).
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
          .accessibilityAddTraits(.isButton)
          .accessibilityAddTraits(sound.isSelected ? [.isSelected] : [])
          .accessibilityAction { activate() }

        VStack(alignment: .leading, spacing: 2) {
          if showSoundNames {
            HStack(spacing: 4) {
              Text(LocalizedStringKey(sound.title))
                .font(.callout)
              if sound.isMusic {
                MusicTagBadge(
                  isActive: sound.isSelected && isGloballyPlaying, accentColor: accent)
              }
            }
            // The slider carries the title for VoiceOver, so hide the visible
            // copy to avoid a double announcement.
            .accessibilityHidden(true)
          }
          Slider(
            value: Binding(
              get: { Double(sound.volume) },
              set: { sound.volume = Float($0) }
            ),
            in: 0...1
          )
          .controlSize(.small)
          .tint(sound.isSelected ? accent : Color.gray)
          .disabled(!sound.isSelected)
          .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
        }
      }
      .padding(.vertical, 2)
      .contentShape(Rectangle())
      .onTapGesture { activate() }
    }
  }

  /// Menu bar label — Blankie's brand glyph.
  struct MenuBarLabel: View {
    var body: some View {
      Image("blankie.symbol")
    }
  }
#endif
