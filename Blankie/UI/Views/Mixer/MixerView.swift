//
//  MixerView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI
import TipKit
import os

// Animation trigger struct to consolidate multiple animation values
private struct AnimationTrigger: Equatable {
  let soloMode: UUID?
  let quickMix: Bool
  let listView: Bool
  let isLoading: Bool
}

/// The iPhone stack's pushed pages. The Library is the stack ROOT (spatially
/// to the left); the mixer is the only pushed destination.
private enum IPhonePage: Hashable {
  case mixer
}

#if os(iOS) || os(visionOS)
  struct MixerView: View {
    @State var audioManager = AudioManager.shared
    @State var globalSettings = GlobalSettings.shared
    @State var presetManager = PresetManager.shared
    @ObservedObject private var appState = AppState.shared
    /// iPhone navigation path. The Library is the stack's root and the app
    /// launches with the mixer pushed on top, so the mixer's back button (or
    /// an edge swipe) leads left to the Library.
    @State private var iPhonePath: [IPhonePage] = [.mixer]
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State var showingSoundManagement = false
    @State var showingSettings = false
    @State var showingQuickMixEditor = false
    @State var soundToEdit: Sound?
    /// Keeps the solo backdrop up while sheet preview temporarily exits solo mode.
    @State private var soloBackdropSound: Sound?
    @State var presetToEdit: Preset?
    /// Confirm-then-create flow replacing Edit Preset on the default preset.
    @State var showingNewPresetConfirmation = false
    @State var showingNewPresetSheet = false
    @State var showingSpatialMixer = false
    @State var showingNowPlaying = false
    @State private var showingVolumeZeroWarning = false
    @State private var isLandscape = false
    // Measured Now Playing bar height, used to inset the iPhone Library list
    // under it (the stack's safeAreaBar doesn't reach that root list).
    @State private var nowPlayingBarHeight: CGFloat = 0
    /// Anchors the zoom transition between the mini bar and the Now Playing cover.
    @Namespace private var nowPlayingNamespace

    // Performance optimization: cached state properties
    @State var cachedFilteredSounds: [Sound] = []
    @State var lastFilterHash: Int = 0
    @State var cachedColumnWidth: CGFloat = 0
    @State var lastScreenWidth: CGFloat = 0
    @State var backgroundImage: PlatformImage?

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
      Group {
        if isLargeDevice {
          iPadLayout
        } else {
          iPhoneLayout
        }
      }
      // A sheet (not a fullScreenCover) so the player has the system's
      // grab-anywhere interactive pull-to-dismiss; the large detent keeps it
      // full-height. The player draws its own drag handle, so hide the system one.
      .sheet(isPresented: $showingNowPlaying) {
        NowPlayingSheet(
          onDismiss: { showingNowPlaying = false },
          backgroundImage: backgroundImage
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .navigationTransition(.zoom(sourceID: "nowPlaying", in: nowPlayingNamespace))
      }
      .sheet(item: $soundToEdit) { sound in
        SoundSheet(mode: .edit(sound))
          .interactiveDismissDisabled()  // Prevent accidental dismissal
          .onAppear {
            Logger.ui.debug("MixerView: SoundSheet appeared for '\(sound.title)'")
          }
          .onDisappear {
            Logger.ui.debug("MixerView: SoundSheet disappeared for '\(sound.title)'")
          }
      }
      .onChange(of: soundToEdit) { oldValue, newValue in
        if let sound = newValue {
          soloBackdropSound = audioManager.soloModeSound
          Logger.ui.debug("MixerView: SoundSheet will be presented for '\(sound.title)'")
        } else if let oldSound = oldValue {
          soloBackdropSound = nil
          Logger.ui.debug("MixerView: SoundSheet will be dismissed for '\(oldSound.title)'")
        }
      }
      // Launch nag when Mix With Other Audio is on but Blankie's volume with
      // media is zeroed — playback would be silent (mirrors Music.app's
      // volume warning on macOS).
      .onAppear {
        if VolumeZeroWarning.shouldWarn() {
          VolumeZeroWarning.markShown()
          showingVolumeZeroWarning = true
        }
      }
      .alert(
        "Blankie's volume with other media is turned all the way down.",
        isPresented: $showingVolumeZeroWarning
      ) {
        Button("OK") {}
        Button("Don't Warn Again") {
          VolumeZeroWarning.suppress()
        }
      } message: {
        Text("To change it, adjust 'Blankie Volume with Media' in Settings.")
      }
      // Onboarding just created (and applied) a preset — land on it: close
      // Settings if it hosted the onboarding, and show the mixer.
      .onChange(of: appState.onboardingCreatedPreset) { _, created in
        guard created else { return }
        appState.onboardingCreatedPreset = false
        showingSettings = false
        iPhonePath = [.mixer]
      }

      .sheet(isPresented: $showingSoundManagement) {
        NavigationStack {
          SoundManagementView()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                  showingSoundManagement = false
                }
              }
            }
        }
        .onDisappear {
          Logger.ui.debug("MixerView: SoundManagementView closed")
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .sheet(isPresented: $showingQuickMixEditor) {
        QuickMixEditorSheet()
      }
      .sheet(isPresented: $showingSpatialMixer) {
        SpatialMixerView()
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
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
          .onDisappear {
            Logger.ui.debug("MixerView: EditPresetSheet closed")

            // CRITICAL: Re-establish media controls after sheet dismissal
            // Animated artwork video preview may have caused iOS to disconnect remote command handlers
            // We restore controls regardless of play state since the gallery may have been browsed
            Logger.ui.debug("MixerView: Restoring media controls after sheet dismissal")
            audioManager.setupMediaControls()
          }
      }
      .modifier(AudioErrorHandler())
      // Sound add/remove, preset switches, and preset edits all flow through
      // @Observable reads now (audioManager.sounds, presetManager.currentPreset),
      // so the grid refreshes automatically — no manual trigger needed. Only the
      // Quick Mix transition keeps a handler, since it has navigation side effects.
      .onChange(of: audioManager.isQuickMix) { _, isQuickMix in
        // Quick Mix is a grid-first mode — entering it (e.g. from the preset
        // picker) always lands on the mixer, never the Now Playing view.
        if isQuickMix { showingNowPlaying = false }
      }
    }

    /// App-wide Grid/List preference. Read live from GlobalSettings so changes
    /// made in the Settings sheet take effect immediately — a local @State
    /// mirror would only refresh on the next view appearance.
    var showingListView: Bool {
      globalSettings.showingListView
    }

    // MARK: - Layouts

    @ViewBuilder
    private var iPadLayout: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarContentView(
          showingSettings: $showingSettings
        )
      } detail: {
        NavigationStack {
          ZStack {
            presetBackgroundView
            VStack(spacing: 0) {
              mainContentView
            }
          }
          // Plain inline title, matching iPhone. The Library now lives in the
          // sidebar, so the title is no longer a picker trigger.
          .navigationTitle(navigationTitle)
          .navigationBarTitleDisplayMode(.inline)
          // The NavigationSplitView owns the sidebar toggle and keeps it
          // available in the detail when collapsed, so we add no reveal control.
          .toolbarBackground(.hidden, for: .navigationBar)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              topTrailingToolbarButton
            }
          }
        }
        // Playback controls must be reachable at every size class. Without
        // this, iPad at regular horizontal size shows no play/pause at all
        // (compact width falls back to iPhoneLayout, which does include it).
        .nowPlayingBottomBar {
          nowPlayingBar
        }
      }
      .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var iPhoneLayout: some View {
      // The Library is the stack's ROOT, to the LEFT of the mixer: the app
      // launches with the mixer pushed on top, the mixer's back button slides
      // left to the Library, and selecting any Library row pushes the mixer
      // again. Settings is a further push from the Library's leading gear —
      // as the root, the Library has no back button competing for that edge.
      NavigationStack(path: $iPhonePath) {
        LibraryView(
          presentation: .page,
          onOpenSettings: { showingSettings = true },
          onSelection: { iPhonePath = [.mixer] },
          backgroundImage: backgroundImage,
          bottomBarHeight: nowPlayingBarHeight
        )
        .navigationDestination(for: IPhonePage.self) { _ in
          mixerPage
        }
      }
      // Attached to the stack, not a page, so the bar persists across the
      // Library root and the pushed mixer.
      .nowPlayingBottomBar {
        nowPlayingBar
      }
    }

    /// On the iPhone stack's Library root, the bar tap steps "in" to the mixer
    /// instead of expanding the player (Library → mixer → full player); from
    /// the mixer — and always on iPad, where the mixer is the ever-present
    /// detail — it expands Now Playing.
    private var barShowsMixer: Bool {
      !isLargeDevice && iPhonePath.isEmpty
    }

    /// Mini player pinned above the bottom safe area; the zoom transition into
    /// the Now Playing cover originates from it.
    private var nowPlayingBar: some View {
      NowPlayingBar(showsMixer: barShowsMixer) {
        if barShowsMixer {
          iPhonePath = [.mixer]
        } else {
          showingNowPlaying = true
        }
      }
      .matchedTransitionSource(id: "nowPlaying", in: nowPlayingNamespace)
      .padding(.horizontal, 16)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        nowPlayingBarHeight = $0
      }
    }

    @ViewBuilder
    private var mixerPage: some View {
      ZStack {
        // Background layer
        presetBackgroundView

        #if os(iOS)
          // Hidden volume view to globally suppress the system volume HUD
          // when physical hardware buttons are pressed.
          SystemVolumeSlider()
            .frame(width: 0, height: 0)
            .opacity(0.001)
            .allowsHitTesting(false)
        #endif

        // Main content
        VStack(spacing: 0) {
          mainContentView
        }
      }
      .onGeometryChange(for: Bool.self) { geo in
        geo.size.width > geo.size.height
      } action: { newValue in
        isLandscape = newValue
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          topTrailingToolbarButton
        }
      }
    }

    // MARK: - Main Content

    private var soloLayoutSound: Sound? {
      if let solo = audioManager.soloModeSound, audioManager.previewModeSound == nil {
        return solo
      }
      if soundToEdit != nil {
        return soloBackdropSound
      }
      return nil
    }

    @ViewBuilder
    private var mainContentView: some View {
      Group {
        if presetManager.isLoading {
          // Until the restore completes, currentPreset is nil and the grid would
          // flash every sound (reading as the default preset). Show nothing over
          // the neutral background; content fades in once the preset is applied.
          Color.clear
        } else if let soloSound = soloLayoutSound {
          soloModeView(for: soloSound)
        } else if audioManager.isQuickMix {
          // Quick Mix mode view
          QuickMixView()
        } else {
          // Normal content: list or grid based on user preference (iPad).
          soundsView
        }
      }
      .animation(
        .easeInOut(duration: 0.3),
        value: AnimationTrigger(
          soloMode: soloLayoutSound?.id,
          quickMix: audioManager.isQuickMix,
          listView: showingListView,
          isLoading: presetManager.isLoading
        )
      )
      .onChange(of: audioManager.soloModeSound) { oldValue, newValue in
        if let newSolo = newValue {
          Logger.ui.debug(
            "MixerView: Solo mode started for '\(newSolo.title)' (SoundSheet open: \(soundToEdit != nil))"
          )
        } else if let oldSolo = oldValue {
          Logger.ui.debug(
            "MixerView: Solo mode ended for '\(oldSolo.title)' (SoundSheet open: \(soundToEdit != nil))"
          )
        }
      }
    }

    // MARK: - Helper Views

    // Helper computed properties are implemented in MixerView+UIComponents.swift
  }

  extension View {
    /// `safeAreaBar` keeps scroll edge effects correct under the mini player.
    func nowPlayingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
      safeAreaBar(edge: .bottom) { bar() }
    }
  }

  #Preview("iPhone") {
    MixerView()
  }

  #Preview("iPad") {
    MixerView()
  }
#endif

#if os(iOS) || os(visionOS)
  extension MixerView {
    // MARK: - Solo Mode View

    @ViewBuilder
    func soloModeView(for soloSound: Sound) -> some View {
      VStack {
        Spacer()
        SoloSoundIcon(sound: soloSound)
          .transition(
            .asymmetric(
              insertion: .scale.combined(with: .opacity),
              removal: .scale.combined(with: .opacity)
            )
          )
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding()
    }

    // MARK: - List View

    @ViewBuilder
    var listView: some View {
      soundListView
    }

    // MARK: - Grid (tile) View

    @ViewBuilder
    var gridView: some View {
      SoundGridView(sounds: filteredSounds, onMove: moveItems)
    }

    /// Resolved view mode for the current context: per-preset override wins
    /// over the app-wide default. Solo mode and Quick Mix have their own
    /// rendering paths and don't route through here.
    var effectiveUseListView: Bool {
      if let override = presetManager.currentPreset?.viewMode {
        return override == .list
      }
      return showingListView
    }

    /// Chooses list or grid view based on per-preset override then app
    /// setting. Grid is the tile layout (matches Quick Mix visually).
    @ViewBuilder
    var soundsView: some View {
      if effectiveUseListView {
        listView
      } else {
        gridView
      }
    }

    @ViewBuilder
    private func soundRow(for sound: Sound) -> some View {
      SoundRowView(sound: sound, globalSettings: globalSettings, audioManager: audioManager)
    }
  }
#endif
