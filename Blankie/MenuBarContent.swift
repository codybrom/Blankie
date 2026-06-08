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
      case .timer:
        circleButton("chevron.backward") { go(to: .mixer) }
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
        // Start/cancel navigates back, not dismiss (which closes the popover).
        TimerView(onFinish: { go(to: .mixer) })
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
                MenuBarSoundRow(sound: sound)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 4)
              }
            }
            .background(
              GeometryReader { proxy in
                Color.clear
                  .onChange(of: proxy.size.height, initial: true) { _, height in
                    listContentHeight = height
                  }
              }
            )
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

    /// Mirrors `ContentView.filteredSounds`: a custom preset shows only its own
    /// sounds, otherwise all but preset-use-only; sorted by the active order.
    private var filteredSounds: [Sound] {
      let visible = audioManager.getVisibleSounds().filter { sound in
        if let preset = presetManager.currentPreset, !preset.isDefault {
          return preset.soundStates.contains { $0.fileName == sound.fileName }
        } else {
          return !sound.isPresetUseOnly
        }
      }
      let order: [String]
      if let preset = presetManager.currentPreset, !preset.isDefault,
        let soundOrder = preset.soundOrder
      {
        order = soundOrder
      } else {
        order = audioManager.defaultSoundOrder
      }
      let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
      return visible.sorted { (rank[$0.fileName] ?? Int.max) < (rank[$1.fileName] ?? Int.max) }
    }

    /// Mixer title: solo sound, Quick Mix, or the preset name.
    private var mixerTitle: String {
      if let solo = audioManager.soloModeSound { return solo.title }
      if audioManager.isQuickMix { return "Quick Mix" }
      return presetManager.currentPreset?.displayName ?? "Blankie"
    }

    /// Active accent: a theming preset's color wins; app accent in solo/Quick Mix.
    private var activeAccent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
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

        Image(systemName: "speaker.wave.2.fill")
          .foregroundStyle(.secondary)
        Slider(
          value: Binding(
            get: { globalSettings.volume },
            set: { globalSettings.setVolume($0) }
          ),
          in: 0...1
        )
        .controlSize(.small)
        .tint(activeAccent)

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
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
  }

  /// Compact list row mirroring iOS `SoundRowView` (glass icon + title + inline
  /// volume slider). Tap toggles the sound and starts playback if paused.
  private struct MenuBarSoundRow: View {
    @ObservedObject var sound: Sound
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var globalSettings = GlobalSettings.shared
    @ObservedObject private var presetManager = PresetManager.shared

    /// A custom preset's color overrides the sound's; otherwise the app accent.
    private var accent: Color {
      if let preset = presetManager.currentPreset, !preset.isDefault,
        let presetColor = preset.accentColor
      {
        return presetColor
      }
      return globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
      HStack(spacing: 14) {
        Image(systemName: sound.systemIconName)
          .font(.system(size: 20))
          .foregroundStyle(
            !audioManager.isGloballyPlaying
              ? Color.gray : (sound.isSelected ? accent : Color.gray)
          )
          .frame(width: 40, height: 40)
          .glassEffect(
            sound.isSelected && audioManager.isGloballyPlaying
              ? .regular.tint(accent.opacity(0.5)).interactive()
              : .regular.interactive(),
            in: .circle
          )
          .opacity(sound.isSelected ? 1.0 : 0.4)

        VStack(alignment: .leading, spacing: 2) {
          Text(LocalizedStringKey(sound.title))
            .font(.callout)
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
        }
      }
      .padding(.vertical, 2)
      .contentShape(Rectangle())
      .onTapGesture {
        sound.toggle()
        if sound.isSelected && !audioManager.isGloballyPlaying {
          audioManager.setGlobalPlaybackState(true)
        }
      }
    }
  }

  /// Menu bar label — Blankie's brand glyph.
  struct MenuBarLabel: View {
    var body: some View {
      Image("blankie.symbol")
    }
  }
#endif
