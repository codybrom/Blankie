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
    @Binding var showingAbout: Bool
    @Binding var showingShortcuts: Bool

    @ObservedObject private var appState = AppState.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    @ObservedObject private var timerManager = TimerManager.shared

    @State private var showingTimerPopover = false
    @State private var showingSpatialMixer = false
    @State private var soundToEdit: Sound?
    /// Keeps the solo backdrop up while sheet preview temporarily exits solo
    /// mode (mirrors MixerView) — otherwise the preset grid pops in behind the
    /// Edit Sound sheet, with paused tiles still styled as playing.
    @State private var soloBackdropSound: Sound?
    @State private var presetToEdit: Preset?
    @State private var showingColorPicker = false
    @State private var showingPreferences = false

    private var filteredSounds: [Sound] {
      let visible = audioManager.getVisibleSounds().filter { sound in
        // A custom preset shows only its own sounds.
        // The default preset (or no preset) shows all sounds.
        let inCurrentPreset: Bool
        if let preset = presetManager.currentPreset, !preset.isDefault {
          inCurrentPreset = preset.soundStates.contains { $0.fileName == sound.fileName }
        } else {
          inCurrentPreset = true
        }
        return inCurrentPreset
      }

      // Sort by the active order so the grid is stable and reorders persist
      // across launches (mirrors iOS MixerView). A custom preset uses its own
      // `soundOrder`; otherwise the global `defaultSoundOrder`.
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

    /// Titlebar subtitle: a running sleep timer wins (same string as the iOS
    /// Now Playing bar), then "Spatial Mix" while the pane replaces the grid
    /// (its only label — the pane itself has no heading). Empty hides it.
    private var windowSubtitle: String {
      if timerManager.isTimerActive, let endTime = timerManager.getEndTime() {
        return String(
          localized: "Pausing at \(endTime.formatted(date: .omitted, time: .shortened))")
      }
      if showingSpatialMixer, spatialEntryAvailable {
        return String(localized: "Spatial Mix")
      }
      return ""
    }

    var body: some View {
      VStack(spacing: 0) {
        if !audioManager.isGloballyPlaying {
          HStack {
            Image(systemName: "pause.circle.fill")
              .accessibilityHidden(true)
            Text("Playback Paused")
              .font(
                Locale.current.identifier.hasPrefix("zh")
                  ? .system(.callout, design: .rounded).weight(.medium)
                  : .system(.subheadline, design: .rounded))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial)
          .foregroundStyle(.secondary)
        }

        // Main content: the spatial mixer replaces the grid while toggled on
        // (preset mode only); solo mode swaps the grid for one large icon with
        // no volume slider (mirrors MixerView's soloModeView); otherwise the
        // shared long-press lift-and-reorder grid with SoundIcon tiles.
        if showingSpatialMixer, spatialEntryAvailable {
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
            // Play/Pause button — visually centered in the bar
            Button(action: {
              audioManager.togglePlayback()
            }) {
              ZStack {
                Circle()
                  .fill(activeAccent.opacity(0.2))
                  .frame(width: 50, height: 50)

                Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 20, height: 20)
                  .foregroundColor(activeAccent)
                  .offset(x: audioManager.isGloballyPlaying ? 0 : 2)
              }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(audioManager.isGloballyPlaying ? "Pause" : "Play")

            HStack(spacing: 16) {
              // Always-visible All Sounds volume (app-level, for multi-output
              // setups — same idea as Music/Spotify's in-app volume).
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 16, height: 16)
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
              Button(action: {
                showingTimerPopover.toggle()
              }) {
                Image(systemName: "timer")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 20, height: 20)
                  .foregroundColor(timerManager.isTimerActive ? activeAccent : .primary)
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Sleep Timer")
              .popover(isPresented: $showingTimerPopover, arrowEdge: .top) {
                TimerView()
              }

              // Color picker menu
              Button(action: {
                showingColorPicker.toggle()
              }) {
                Image(systemName: "paintpalette.fill")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 20, height: 20)
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
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .background(.ultraThinMaterial)
      }

      .navigationTitle(navigationTitle)
      .navigationSubtitle(windowSubtitle)
      // Floating title: merge the detail's toolbar strip into the content,
      // mirroring the iPad detail's hidden navigation-bar background.
      .toolbarBackground(.hidden, for: .windowToolbar)
      .toolbar {
        // Spatial mixer toggle — preset mode only, and only when the user has
        // opted into the experimental feature. Swaps the grid for the mixer
        // pane; accent tint marks the pane as showing.
        if spatialEntryAvailable {
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
        // or the current preset (mirrors iOS's topTrailingToolbarButton).
        ToolbarItem(placement: .primaryAction) {
          Button {
            if let soloSound = audioManager.soloModeSound {
              soundToEdit = soloSound
            } else if let currentPreset = presetManager.currentPreset {
              presetToEdit = currentPreset
            }
          } label: {
            Image(systemName: "slider.vertical.3")
          }
          .accessibilityLabel(audioManager.soloModeSound != nil ? "Edit Sound" : "Edit Preset")
          .disabled(audioManager.soloModeSound == nil && presetManager.currentPreset == nil)
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
      .animation(.easeInOut(duration: 0.2), value: audioManager.isGloballyPlaying)
      .animation(.easeInOut(duration: 0.3), value: audioManager.soloModeSound?.id)
      .animation(.easeInOut(duration: 0.2), value: showingSpatialMixer)
      .sheet(isPresented: $showingShortcuts) {
        ShortcutsView()
          .background(.ultraThinMaterial)
          .presentationBackground(.ultraThinMaterial)
      }
      .sheet(isPresented: $showingAbout) {
        AboutView()
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
        if !audioManager.isGloballyPlaying {
          NSApp.dockTile.badgeLabel = "⏸"
        } else {
          NSApp.dockTile.badgeLabel = nil
        }
      }
      .onChange(of: audioManager.isGloballyPlaying) {
        if !audioManager.isGloballyPlaying {
          NSApp.dockTile.badgeLabel = "⏸"
        } else {
          NSApp.dockTile.badgeLabel = nil
        }
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
        UserDefaults.standard.set(complete, forKey: "defaultSoundOrder")
        audioManager.objectWillChange.send()
      }
    }

    private func handleMenuImport(_ result: Result<[URL], Error>) {
      guard case .success(let urls) = result, let url = urls.first else { return }
      AudioFileImporter.shared.handleIncomingFile(url)
    }
  }

  struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
      Group {
        ContentView(
          showingAbout: .constant(false),
          showingShortcuts: .constant(false)
        )
        .frame(width: 600, height: 400)
      }
      .previewDisplayName("Blankie")
    }
  }
#endif
