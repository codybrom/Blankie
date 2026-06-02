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
    @Binding var showingNewPresetPopover: Bool
    @Binding var presetName: String

    @ObservedObject private var appState = AppState.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    @State private var showingVolumePopover = false
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
        return inCurrentPreset && (!appState.hideInactiveSounds || sound.isSelected)
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

    /// Active accent: the current preset's color takes precedence over the
    /// global setting, matching the grid tiles and iOS behavior.
    private var activeAccent: Color {
      presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
      VStack(spacing: 0) {
        if !audioManager.isGloballyPlaying {
          HStack {
            Image(systemName: "pause.circle.fill")
            Text("Playback Paused")
              .font(
                Locale.current.identifier.hasPrefix("zh")
                  ? .system(size: 16, weight: .medium, design: .rounded)
                  : .system(.subheadline, design: .rounded))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial)
          .foregroundStyle(.secondary)
        }

        // Main content: the shared long-press lift-and-reorder grid (same
        // engine as iOS), with SoundIcon tiles.
        MacSoundGridView(
          sounds: filteredSounds,
          onMove: { from, to in
            moveSounds(from: from, to: to)
          }
        )
        .padding()
        .frame(maxHeight: .infinity)

        // App bar
        VStack(spacing: 0) {
          Rectangle()
            .frame(height: 1)
            .foregroundColor(Color.gray.opacity(0.2))

          HStack(spacing: 16) {
            // Volume button with popover
            Button(action: {
              showingVolumePopover.toggle()
            }) {
              Image(systemName: "speaker.wave.2.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(.primary)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("volumeButton")
            .accessibilityLabel("Volume")
            .popover(isPresented: $showingVolumePopover, arrowEdge: .top) {
              VolumePopoverView()
            }

            // Play/Pause button
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
          .padding(.vertical, 12)
          .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .background(.ultraThinMaterial)
      }

      .ignoresSafeArea(.container, edges: .horizontal)
      .animation(.easeInOut(duration: 0.2), value: audioManager.isGloballyPlaying)
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
        showingVolumePopover = false
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
          showingShortcuts: .constant(false),
          showingNewPresetPopover: .constant(false),
          presetName: .constant("")
        )
        .frame(width: 600, height: 400)
      }
      .previewDisplayName("Blankie")
    }
  }
#endif
