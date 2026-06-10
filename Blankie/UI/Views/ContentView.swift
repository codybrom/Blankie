//
//  ContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  struct ContentView: View {
    @Binding var showingShortcuts: Bool

    @ObservedObject private var appState = AppState.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    @State private var showingTimerPopover = false
    @State private var showingSpatialMixer = false
    @State private var soundToEdit: Sound?
    /// Keeps the solo backdrop up while sheet preview temporarily exits solo
    /// mode (mirrors MixerView) — otherwise the preset grid pops in behind the
    /// Edit Sound sheet, with paused tiles still styled as playing.
    @State private var soloBackdropSound: Sound?
    @State private var presetToEdit: Preset?
    /// Confirm-then-create flow replacing Edit Preset on the default preset.
    @State private var showingNewPresetConfirmation = false
    @State private var showingNewPresetSheet = false
    @State private var showingColorPicker = false
    @State private var showingPreferences = false
    @State private var isHoveringPlayButton = false

    private var filteredSounds: [Sound] {
      audioManager.orderedVisibleSounds(for: presetManager.currentPreset)
    }

    var textColor: Color {
      audioManager.isGloballyPlaying ? .primary : .secondary
    }

    /// Active accent: the theming preset's color takes precedence over the
    /// global setting, matching the grid tiles and iOS behavior. `themingPreset`
    /// is nil during solo / Quick Mix, so those use the app accent.
    private var activeAccent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    /// Whether the Spatial Mix toggle (and pane) is available: opted in via
    /// Preferences, preset mode only — mirrors iOS's gating.
    private var spatialEntryAvailable: Bool {
      globalSettings.enableSpatialAudio
        && audioManager.soloModeSound == nil && !audioManager.isQuickMix
        && presetManager.currentPreset != nil
    }

    /// The sound whose solo view should fill the detail pane: the real solo
    /// (when not previewing), or the captured backdrop while the Edit Sound
    /// sheet is up (mirrors MixerView's soloLayoutSound).
    private var soloLayoutSound: Sound? {
      if let solo = audioManager.soloModeSound, audioManager.previewModeSound == nil {
        return solo
      }
      if soundToEdit != nil {
        return soloBackdropSound
      }
      return nil
    }

    /// Window titlebar context, mirroring iOS MixerView: solo sound name, then
    /// Quick Mix, then the current preset name (default preset shows "Blankie").
    private var navigationTitle: String {
      // soloLayoutSound (not soloModeSound) so the title doesn't flip to the
      // preset name while sheet preview temporarily exits solo mode.
      if let soloSound = soloLayoutSound {
        return soloSound.title
      }
      if audioManager.isQuickMix {
        return String(localized: "Quick Mix")
      }
      if let preset = presetManager.currentPreset {
        return preset.isDefault ? "Blankie" : preset.name
      }
      return "Blankie"
    }

    /// Play would be silent: paused with nothing selected. Pause is never
    /// blocked — a silent "playing" state still needs a way out.
    private var playButtonDisabled: Bool {
      !audioManager.isGloballyPlaying && !audioManager.hasSelectedSounds
    }

    /// Top-of-window strip explaining why nothing is audible; tint at the call
    /// site.
    private func statusBanner(_ title: LocalizedStringKey, systemImage: String) -> some View {
      HStack {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
        Text(title)
          .font(
            Locale.current.identifier.hasPrefix("zh")
              ? .system(.callout, design: .rounded).weight(.medium)
              : .system(.subheadline, design: .rounded))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    }

    var body: some View {
      VStack(spacing: 0) {
        // Silence explained: an empty selection wins over the paused state
        // (play alone can't help there), accent-tinted to draw the eye.
        // Suppressed while Settings holds the pane — the banner explains the
        // grid, which isn't on screen (like the toolbar's mixer actions).
        if !appState.showingSettingsPane {
          if audioManager.soloModeSound == nil && !audioManager.hasSelectedSounds {
            statusBanner("No Sounds Playing", systemImage: "speaker.slash.circle.fill")
              .foregroundStyle(activeAccent)
          } else if !audioManager.isGloballyPlaying {
            statusBanner("Playback Paused", systemImage: "pause.circle.fill")
              .foregroundStyle(.secondary)
          }
        }

        // Main content: Settings takes over the pane while the sidebar gear is
        // active; the spatial mixer replaces the grid while toggled on
        // (preset mode only); solo mode swaps the grid for one large icon with
        // no volume slider (mirrors MixerView's soloModeView); otherwise the
        // shared long-press lift-and-reorder grid with SoundIcon tiles.
        if appState.showingSettingsPane {
          SettingsView(isPane: true)
            .transition(.opacity)
        } else if showingSpatialMixer, spatialEntryAvailable {
          SpatialMixerView()
            .transition(.opacity)
        } else if let soloSound = soloLayoutSound {
          VStack {
            Spacer()
            SoloSoundIcon(sound: soloSound)
              .transition(.scale.combined(with: .opacity))
            Spacer()
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()
        } else {
          MacSoundGridView(
            sounds: filteredSounds,
            onMove: { from, to in
              moveSounds(from: from, to: to)
            }
          )
          .padding()
          .frame(maxHeight: .infinity)
        }

        // App bar
        VStack(spacing: 0) {
          Rectangle()
            .frame(height: 1)
            .foregroundColor(Color.gray.opacity(0.2))

          ZStack {
            // Play/Pause button — visually centered in the bar. Disabled only
            // when play would be silent (paused with nothing selected); pause
            // stays available whenever global playback is on.
            Button(action: {
              audioManager.togglePlayback()
            }) {
              ZStack {
                Circle()
                  .fill((playButtonDisabled ? Color.gray : activeAccent).opacity(0.2))
                  .frame(width: 50, height: 50)

                // Render as a font glyph, not .resizable, so the SF Symbol keeps
                // its built-in optical centering (matches the grid/list).
                Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
                  .font(.system(size: 20))
                  .foregroundColor(playButtonDisabled ? .secondary : activeAccent)
                  .offset(x: audioManager.isGloballyPlaying ? 0 : 2)
              }
            }
            .buttonStyle(.borderless)
            .disabled(playButtonDisabled)
            .help(audioManager.isGloballyPlaying ? "Pause" : "Play")
            .accessibilityLabel(audioManager.isGloballyPlaying ? "Pause" : "Play")
            // Instant hover hint for the silent state — the system tooltip's
            // fixed delay reads as unresponsive. Outside .disabled's scope so
            // hover still tracks while the button is disabled.
            .onHover { isHoveringPlayButton = $0 }
            .overlay(alignment: .bottom) {
              if isHoveringPlayButton && !audioManager.hasSelectedSounds {
                Text("No Sounds Playing")
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(.regularMaterial, in: Capsule())
                  .fixedSize()
                  .offset(y: -58)
                  .allowsHitTesting(false)
                  .transition(.opacity)
              }
            }
            .animation(.easeInOut(duration: 0.15), value: isHoveringPlayButton)

            HStack(spacing: 16) {
              // Always-visible All Sounds volume (app-level, for multi-output
              // setups — same idea as Music/Spotify's in-app volume).
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .font(.system(size: 16))
                  .foregroundColor(.secondary)
                  .accessibilityHidden(true)

                Slider(
                  value: Binding(
                    get: { globalSettings.volume },
                    set: { globalSettings.setVolume($0) }
                  ),
                  in: 0...1
                )
                .frame(maxWidth: 130)
                .controlSize(.small)
                .tint(activeAccent)
                .accessibilityLabel(Text("All Sounds"))
                .accessibilityValue(
                  Text(globalSettings.volume.formatted(.percent.precision(.fractionLength(0)))))
              }

              Spacer()

              // Sleep timer
              SleepTimerButton(
                activeAccent: activeAccent, showingPopover: $showingTimerPopover)

              // Color picker menu
              Button(action: {
                showingColorPicker.toggle()
              }) {
                Image(systemName: "paintpalette.fill")
                  .font(.system(size: 20))
                  .foregroundColor(.primary)
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Accent Color")
              .popover(isPresented: $showingColorPicker) {
                ColorPickerView()
                  .padding()
              }
            }
          }
          .padding(.vertical, 12)
          .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
      }
      .containerBackground(.ultraThinMaterial, for: .window)

      .navigationTitle(navigationTitle)
      .modifier(
        WindowSubtitleModifier(
          spatialMixerActive: showingSpatialMixer && spatialEntryAvailable
            && !appState.showingSettingsPane)
      )
      // Floating title: merge the detail's toolbar strip into the content,
      // mirroring the iPad detail's hidden navigation-bar background. The
      // Settings pane scrolls a form under the title, so it gets the standard
      // backed toolbar instead.
      .toolbarBackground(
        appState.showingSettingsPane ? .visible : .hidden, for: .windowToolbar
      )
      .toolbar {
        // Both mixer actions hide while Settings holds the pane — they act on
        // the grid content, which isn't on screen (Settings brings its own
        // Done button).
        // Spatial mixer toggle — preset mode only, and only when the user has
        // opted into the experimental feature. Swaps the grid for the mixer
        // pane; accent tint marks the pane as showing.
        if spatialEntryAvailable, !appState.showingSettingsPane {
          ToolbarItem(placement: .primaryAction) {
            Button {
              showingSpatialMixer.toggle()
            } label: {
              Image(systemName: "speaker.wave.1.arrowtriangles.up.right.down.left")
                .foregroundStyle(showingSpatialMixer ? activeAccent : Color.primary)
            }
            .accessibilityLabel(Text("Spatial Mix"))
          }
        }
        // Edit affordance for whatever is on screen — the solo sound's editor
        // or the current preset (mirrors iOS's topTrailingToolbarButton). The
        // default preset has no editor, so there the slot offers to start a
        // new preset from the playing sounds (confirm, then the creator).
        if !appState.showingSettingsPane {
          ToolbarItem(placement: .primaryAction) {
            let onDefaultPreset =
              audioManager.soloModeSound == nil
              && presetManager.currentPreset?.isDefault == true
            Button {
              if let soloSound = audioManager.soloModeSound {
                soundToEdit = soloSound
              } else if let currentPreset = presetManager.currentPreset {
                if currentPreset.isDefault {
                  showingNewPresetConfirmation = true
                } else {
                  presetToEdit = currentPreset
                }
              }
            } label: {
              Image(systemName: onDefaultPreset ? "square.and.pencil" : "slider.vertical.3")
            }
            .accessibilityLabel(
              audioManager.soloModeSound != nil
                ? "Edit Sound" : onDefaultPreset ? "New Preset" : "Edit Preset"
            )
            // New Preset also needs playing sounds — nothing to seed otherwise.
            .disabled(
              audioManager.soloModeSound == nil
                && (presetManager.currentPreset == nil
                  || (onDefaultPreset && !audioManager.hasSelectedSounds))
            )
          }
        }
      }
      .sheet(item: $soundToEdit) { sound in
        SoundSheet(mode: .edit(sound))
          .interactiveDismissDisabled()  // Prevent accidental dismissal
      }
      // Capture the solo backdrop for the sheet's lifetime (mirrors MixerView).
      .onChange(of: soundToEdit) { oldValue, newValue in
        if newValue != nil {
          soloBackdropSound = audioManager.soloModeSound
        } else if oldValue != nil {
          soloBackdropSound = nil
        }
      }
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
      }
      // The default preset has no editor; its Edit slot offers to start a new
      // preset from whatever is currently playing instead.
      .alert("Create a Preset from Playing Sounds?", isPresented: $showingNewPresetConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Create") { showingNewPresetSheet = true }
      } message: {
        Text("The default preset can't be edited. Start a new preset with your current sounds.")
      }
      .sheet(isPresented: $showingNewPresetSheet) {
        CreatePresetSheet(
          isPresented: $showingNewPresetSheet,
          initialSelectedSounds: Set(audioManager.sounds.filter { $0.isSelected }.map(\.fileName))
        )
      }
      .animation(.easeInOut(duration: 0.2), value: audioManager.isGloballyPlaying)
      .animation(.easeInOut(duration: 0.3), value: audioManager.soloModeSound?.id)
      .animation(.easeInOut(duration: 0.2), value: showingSpatialMixer)
      .animation(.easeInOut(duration: 0.2), value: appState.showingSettingsPane)
      .sheet(isPresented: $showingShortcuts) {
        ShortcutsView()
          .background(.ultraThinMaterial)
          .presentationBackground(.ultraThinMaterial)
      }
      // Debug menu's onboarding trigger (Debug ▸ Show Onboarding).
      .sheet(isPresented: $appState.showingOnboarding) {
        PresetOnboardingSheet(isPresented: $appState.showingOnboarding)
      }
      .sheet(isPresented: $appState.showingManageSounds) {
        NavigationStack {
          SoundManagementView()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { appState.showingManageSounds = false }
              }
            }
        }
      }
      // Menu-bar import (File ▸ Import Sound or Preset). Accepts audio and
      // .blankie files; AudioFileImporter routes audio → add-sound sheet
      // (presented by SharedAppModifiers) and .blankie → preset import.
      .fileImporter(
        isPresented: $appState.showingImport,
        allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .blankiePreset],
        allowsMultipleSelection: false
      ) { result in
        handleMenuImport(result)
      }
      .onAppear {
        setupResetHandler()
        // Launch nag when the app volume is zeroed (mirrors Music.app).
        // Deferred so the window finishes drawing before the modal runs.
        DispatchQueue.main.async {
          VolumeZeroWarning.showIfNeeded()
        }
      }
      // Leaving preset mode (solo, Quick Mix, setting off) hides the spatial
      // pane; drop the toggle too so it doesn't silently reappear on return.
      .onChange(of: spatialEntryAvailable) { _, available in
        if !available { showingSpatialMixer = false }
      }
      // Onboarding just created (and applied) a preset — close the Settings
      // pane if it hosted the onboarding so the grid shows the new preset.
      .onChange(of: appState.onboardingCreatedPreset) { _, created in
        guard created else { return }
        appState.onboardingCreatedPreset = false
        appState.showingSettingsPane = false
      }
      // Manage Sounds (⌘O sheet) takes the window — drop the Settings pane
      // underneath so closing the sheet lands on the preset grid. (Sub-page
      // flags reset via the pane's onDisappear.)
      .onChange(of: appState.showingManageSounds) { _, showing in
        guard showing else { return }
        appState.showingSettingsPane = false
      }
      .modifier(AudioErrorHandler())
    }

    private func setupResetHandler() {
      audioManager.onReset = { @MainActor in
        showingTimerPopover = false
      }
    }

    /// Persist a grid reorder. `source`/`destination` are indices into the
    /// displayed (`filteredSounds`) order, so we reorder that list of file names
    /// and write the complete order back — to the current custom preset, or to
    /// the global default order. Mirrors iOS `MixerView.moveItems`; the grid then
    /// re-sorts from the persisted order. (The old path moved the full `sounds`
    /// array using filtered-subset indices and never persisted, so it moved the
    /// wrong sound and was lost on relaunch.)
    private func moveSounds(from source: IndexSet, to destination: Int) {
      var newOrder = filteredSounds.map(\.fileName)
      newOrder.move(fromOffsets: source, toOffset: destination)
      let displayed = Set(newOrder)

      if let preset = presetManager.currentPreset, !preset.isDefault {
        // Keep any preset sounds not currently displayed (e.g. hidden) at the end.
        var complete = newOrder
        for state in preset.soundStates where !displayed.contains(state.fileName) {
          complete.append(state.fileName)
        }
        presetManager.updateCurrentPresetWithOrder(complete)
      } else {
        var complete = newOrder
        for fileName in audioManager.defaultSoundOrder where !displayed.contains(fileName) {
          complete.append(fileName)
        }
        audioManager.defaultSoundOrder = complete
        // Must match the suite the order is read back from at launch
        // (UserDefaults.shared / app group); .standard silently reverts.
        UserDefaults.shared.set(complete, forKey: "defaultSoundOrder")
        audioManager.objectWillChange.send()
      }
    }

    private func handleMenuImport(_ result: Result<[URL], Error>) {
      guard case .success(let urls) = result, let url = urls.first else { return }
      AudioFileImporter.shared.handleIncomingFile(url)
    }
  }

  /// Titlebar subtitle: a running sleep timer wins (same string as the iOS
  /// Now Playing bar), then "Spatial Mix" while the pane replaces the grid
  /// (its only label — the pane itself has no heading). Empty hides it.
  /// Owns the TimerManager observation so its per-second tick invalidates only
  /// this modifier, not the whole ContentView body (mirrors iOS, which scopes
  /// the observation to NowPlayingBar).
  private struct WindowSubtitleModifier: ViewModifier {
    private let timerManager = TimerManager.shared
    let spatialMixerActive: Bool

    func body(content: Content) -> some View {
      content.navigationSubtitle(subtitle)
    }

    private var subtitle: String {
      if timerManager.isTimerActive, let endTime = timerManager.getEndTime() {
        return String(
          localized: "Pausing at \(endTime.formatted(date: .omitted, time: .shortened))")
      }
      if spatialMixerActive {
        return String(localized: "Spatial Mix")
      }
      return ""
    }
  }

  /// Bottom-bar sleep timer button. Owns the TimerManager observation so timer
  /// ticks re-render just this button (for the active tint), not ContentView.
  private struct SleepTimerButton: View {
    private let timerManager = TimerManager.shared
    let activeAccent: Color
    @Binding var showingPopover: Bool

    var body: some View {
      Button(action: {
        showingPopover.toggle()
      }) {
        Image(systemName: "timer")
          .font(.system(size: 20))
          .foregroundColor(timerManager.isTimerActive ? activeAccent : .primary)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Sleep Timer")
      .popover(isPresented: $showingPopover, arrowEdge: .top) {
        TimerView()
      }
    }
  }

  #Preview("Blankie") {
    ContentView(
      showingShortcuts: .constant(false)
    )
    .frame(width: 600, height: 400)
  }
#endif
