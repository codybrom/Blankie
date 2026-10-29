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
    let audioManager = AudioManager.shared
    let globalSettings = GlobalSettings.shared
    @State private var presetManager = PresetManager.shared

    @State private var showingTimerPopover = false
    @State private var showingSpatialMixer = false
    @State private var soundToEdit: Sound?
    /// Keeps the single sound backdrop up while sheet preview temporarily exits single sound
    /// mode (mirrors MixerView).
    @State private var singleBackdropSound: Sound?
    @State private var presetToEdit: Preset?
    /// Confirm-then-create flow replacing Edit Preset on the default preset.
    @State private var showingNewPresetConfirmation = false
    @State private var showingAddSound = false
    @State private var showingSaveMix = false
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

    /// `themingPreset` is nil during single sound and Quick Mix, so those use the app accent.
    private var activeAccent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    /// The preset whose artwork backs the tiles, while they're on screen.
    private var backdropPreset: Preset? {
      guard !presetManager.isLoading, !appState.showingSettingsPane,
        !(showingSpatialMixer && spatialEntryAvailable), singleLayoutSound == nil
      else { return nil }
      return presetManager.themingPreset
    }

    /// Spatial Mix: opted in via Settings, preset mode only (same gating as iOS).
    private var spatialEntryAvailable: Bool {
      globalSettings.enableSpatialAudio
        && audioManager.singleSound == nil && !audioManager.isQuickMix
        && presetManager.currentPreset != nil
    }

    /// The real single sound, or the captured backdrop while Edit Sound is up
    /// (mirrors MixerView).
    private var singleLayoutSound: Sound? {
      if let single = audioManager.singleSound, audioManager.previewModeSound == nil {
        return single
      }
      if soundToEdit != nil {
        return singleBackdropSound
      }
      return nil
    }

    private var navigationTitle: String {
      // singleLayoutSound keeps the title steady while sheet preview exits single sound.
      if let singleSound = singleLayoutSound {
        return singleSound.localizedTitle
      }
      if let unsavedMix = audioManager.unsavedMix {
        return unsavedMix.name
      }
      if audioManager.isQuickMix {
        return String(localized: "Quick Mix")
      }
      if let preset = presetManager.currentPreset {
        return preset.isDefault ? "Blankie" : preset.name
      }
      return "Blankie"
    }

    /// Play would be silent: paused with nothing selected. Pause stays enabled.
    private var playButtonDisabled: Bool {
      !audioManager.isGloballyPlaying && !audioManager.hasSelectedSounds
    }

    /// A hidden banner reserves the strip's height so the visible banner can
    /// animate in and out without reflowing the tiles.
    private var reservedStatusStrip: some View {
      statusBanner("Playback Paused", systemImage: "pause.circle.fill")
        .hidden()
    }

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
        // An empty selection wins over paused. Both stay hidden while Settings
        // holds the pane and while presets load (nothing is selected yet).
        reservedStatusStrip
          .overlay {
            if !appState.showingSettingsPane, !presetManager.isLoading {
              if audioManager.singleSound == nil && !audioManager.hasSelectedSounds {
                statusBanner("No Sounds Playing", systemImage: "speaker.slash.circle.fill")
                  .foregroundStyle(activeAccent)
                  .transition(.opacity)
              } else if !audioManager.isGloballyPlaying {
                statusBanner("Playback Paused", systemImage: "pause.circle.fill")
                  .foregroundStyle(.secondary)
                  .transition(.opacity)
              }
            }
          }

        if presetManager.isLoading {
          // currentPreset is nil until the restore completes.
          Color.clear
        } else if appState.showingSettingsPane {
          SettingsView(isPane: true)
            .transition(.opacity)
        } else if showingSpatialMixer, spatialEntryAvailable {
          SpatialMixerView()
            .transition(.opacity)
        } else if let singleSound = singleLayoutSound {
          VStack {
            Spacer()
            SingleSoundCard(sound: singleSound)
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

        // Mirrors the top strip so the tiles stay vertically centered.
        reservedStatusStrip

        VStack(spacing: 0) {
          Rectangle()
            .frame(height: 1)
            .foregroundColor(Color.gray.opacity(0.2))

          ZStack {
            Button(action: {
              audioManager.togglePlayback()
            }) {
              ZStack {
                Circle()
                  .fill((playButtonDisabled ? Color.gray : activeAccent).opacity(0.2))
                  .frame(width: 50, height: 50)

                Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
                  .font(.system(size: 20))
                  .foregroundColor(playButtonDisabled ? .secondary : activeAccent)
              }
            }
            .buttonStyle(.borderless)
            .disabled(playButtonDisabled)
            .help(audioManager.isGloballyPlaying ? "Pause" : "Play")
            .accessibilityLabel(audioManager.isGloballyPlaying ? "Pause" : "Play")
            // Instant hint for the silent state (the system tooltip has a fixed
            // delay). Outside .disabled's scope so hover tracks while disabled.
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
              // App-level volume, separate from the system output volume.
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

              SleepTimerButton(
                activeAccent: activeAccent, showingPopover: $showingTimerPopover)

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
      .background {
        PresetArtworkBackdrop(
          preset: backdropPreset, blurRadius: globalSettings.backgroundBlurRadius)
      }
      // Opaque: materials wash out over a light desktop.
      .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)

      .navigationTitle(navigationTitle)
      .modifier(
        WindowSubtitleModifier(
          spatialMixerActive: showingSpatialMixer && spatialEntryAvailable
            && !appState.showingSettingsPane)
      )
      // Hidden toolbar background like the iPad detail, except over the
      // Settings form, which scrolls under the title.
      .toolbarBackground(
        appState.showingSettingsPane ? .visible : .hidden, for: .windowToolbar
      )
      .toolbar {
        // Mixer actions hide while Settings holds the pane.
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
        if audioManager.canAddSound, !appState.showingSettingsPane {
          ToolbarItem(placement: .primaryAction) {
            Button {
              showingAddSound = true
            } label: {
              Image(systemName: "plus")
            }
            .accessibilityLabel(Text("Add Sound"))
            .popover(isPresented: $showingAddSound, arrowEdge: .bottom) {
              MixSoundsPicker()
            }
          }
        }
        // An unsaved mix's slot is Save.
        if audioManager.unsavedMix != nil, !appState.showingSettingsPane {
          ToolbarItem(placement: .primaryAction) {
            Button("Save") { showingSaveMix = true }
              .accessibilityLabel(Text("Save Mix"))
          }
        }
        // Mirrors iOS's editToolbarItems, including New Preset on the default preset.
        if audioManager.unsavedMix == nil, !appState.showingSettingsPane {
          ToolbarItem(placement: .primaryAction) {
            let onDefaultPreset =
              audioManager.singleSound == nil
              && presetManager.currentPreset?.isDefault == true
            Button {
              if let singleSound = audioManager.singleSound {
                soundToEdit = singleSound
              } else if let currentPreset = presetManager.currentPreset {
                if currentPreset.isDefault {
                  showingNewPresetConfirmation = true
                } else {
                  presetToEdit = currentPreset
                }
              }
            } label: {
              Image(
                systemName: onDefaultPreset ? "rectangle.stack.badge.plus" : "slider.vertical.3")
            }
            .accessibilityLabel(
              audioManager.singleSound != nil
                ? "Edit Sound" : onDefaultPreset ? "New Preset" : "Edit Preset"
            )
            // New Preset needs playing sounds to seed it.
            .disabled(
              audioManager.singleSound == nil
                && (presetManager.currentPreset == nil
                  || (onDefaultPreset && !audioManager.hasSelectedSounds))
            )
          }
        }
      }
      .sheet(item: $soundToEdit) { sound in
        SoundSheet(mode: .edit(sound))
          .interactiveDismissDisabled()
      }
      .saveMixSheet(isPresented: $showingSaveMix)
      // Capture the single sound backdrop for the sheet's lifetime (mirrors MixerView).
      .onChange(of: soundToEdit) { oldValue, newValue in
        if newValue != nil {
          singleBackdropSound = audioManager.singleSound
        } else if oldValue != nil {
          singleBackdropSound = nil
        }
      }
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
      }
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
      .animation(.easeInOut(duration: 0.3), value: audioManager.singleSound?.id)
      .animation(.easeInOut(duration: 0.2), value: showingSpatialMixer)
      .animation(.easeInOut(duration: 0.2), value: appState.showingSettingsPane)
      .sheet(isPresented: $showingShortcuts) {
        ShortcutsView()
          .background(.ultraThinMaterial)
          .presentationBackground(.ultraThinMaterial)
      }
      // Debug > Show Onboarding.
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
      // File > Import Sound or Preset. AudioFileImporter routes audio to the
      // add-sound sheet and .blankie files to preset import.
      .fileImporter(
        isPresented: $appState.showingImport,
        allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .blankiePreset],
        allowsMultipleSelection: false
      ) { result in
        handleMenuImport(result)
      }
      .onAppear {
        setupResetHandler()
        // Zero-volume warning, deferred so the window draws before the modal.
        DispatchQueue.main.async {
          VolumeZeroWarning.showIfNeeded()
        }
      }
      // Leaving preset mode also clears the toggle, so the pane stays closed on return.
      .onChange(of: spatialEntryAvailable) { _, available in
        if !available { showingSpatialMixer = false }
      }
      // Onboarding created a preset: close Settings to show it.
      .onChange(of: appState.onboardingCreatedPreset) { _, created in
        guard created else { return }
        appState.onboardingCreatedPreset = false
        appState.showingSettingsPane = false
      }
      // Manage Sounds (⌘O) closes the Settings pane so dismissing it lands on the preset.
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

    /// Persists a reorder. Indices are into `filteredSounds`. The order goes to the unsaved
    /// mix, the custom preset or the default order (mirrors `MixerView.moveItems`).
    private func moveSounds(from source: IndexSet, to destination: Int) {
      var newOrder = filteredSounds.map(\.fileName)
      newOrder.move(fromOffsets: source, toOffset: destination)
      let displayed = Set(newOrder)

      if audioManager.unsavedMix != nil {
        audioManager.reorderUnsavedMix(newOrder)
      } else if let preset = presetManager.currentPreset, !preset.isDefault {
        // Hidden preset sounds keep a place at the end.
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
        // Launch reads the order back from the app group suite.
        UserDefaults.shared.set(complete, forKey: "defaultSoundOrder")
      }
    }

    private func handleMenuImport(_ result: Result<[URL], Error>) {
      guard case .success(let urls) = result, let url = urls.first else { return }
      AudioFileImporter.shared.handleIncomingFile(url)
    }
  }

  /// Titlebar subtitle: the sleep timer, else "Spatial Mix" (the pane has no heading).
  /// Owns the TimerManager observation so each tick invalidates only this modifier.
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

  /// Owns the TimerManager observation so ticks re-render only this button.
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
  /// Blurred preset artwork behind the tiles (the Mac's `presetBackgroundView`).
  /// Dimmer than iOS so the glass tiles stay legible at pane size.
  private struct PresetArtworkBackdrop: View {
    let preset: Preset?
    let blurRadius: Double
    @State private var image: NSImage?

    var body: some View {
      GeometryReader { geometry in
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .blur(radius: blurRadius)
            .opacity(0.35)
            .clipped()
            .overlay(Color.black.opacity(0.45))
            // Distinct identity per image so artwork swaps crossfade.
            .id(ObjectIdentifier(image))
            .transition(.opacity)
        }
      }
      .ignoresSafeArea()
      .accessibilityHidden(true)
      .task(
        id:
          "\(preset?.id.uuidString ?? "")-\(preset?.artworkId?.uuidString ?? "")-\(preset?.animatedArtwork?.previewPath ?? "")"
      ) {
        guard let preset else {
          withAnimation(.easeInOut(duration: 0.35)) { image = nil }
          return
        }
        // Keep the old image until the next loads, then crossfade to it.
        let loaded = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
        // Drop a load that finished after the preset changed.
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.35)) { image = loaded }
      }
    }
  }
#endif
