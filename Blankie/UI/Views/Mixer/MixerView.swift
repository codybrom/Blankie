import SwiftUI
import TipKit

// Animation trigger struct to consolidate multiple animation values
private struct AnimationTrigger: Equatable {
  let soloMode: UUID?
  let quickMix: Bool
  let listView: Bool
}

/// The iPhone stack's pushed pages. The Library is the stack ROOT (spatially
/// to the left); the mixer is the only pushed destination.
private enum IPhonePage: Hashable {
  case mixer
}

#if os(iOS) || os(visionOS)
  struct MixerView: View {
    @StateObject var audioManager = AudioManager.shared
    @StateObject var globalSettings = GlobalSettings.shared
    @StateObject var presetManager = PresetManager.shared
    /// iPhone navigation path. The Library is the stack's root and the app
    /// launches with the mixer pushed on top, so the mixer's back button (or
    /// an edge swipe) leads left to the Library.
    @State private var iPhonePath: [IPhonePage] = [.mixer]
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State var showingSoundManagement = false
    @State var showingSettings = false
    @State var showingQuickMixEditor = false
    @State var soundToEdit: Sound?
    @State var presetToEdit: Preset?
    @State var soundsUpdateTrigger = 0
    @State var showingNowPlaying = false
    @State private var isLandscape = false
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
      .fullScreenCover(isPresented: $showingNowPlaying) {
        NowPlayingSheet(
          onDismiss: { showingNowPlaying = false },
          backgroundImage: backgroundImage
        )
        .navigationTransition(.zoom(sourceID: "nowPlaying", in: nowPlayingNamespace))
      }
      .sheet(item: $soundToEdit) { sound in
        SoundSheet(mode: .edit(sound))
          .interactiveDismissDisabled()  // Prevent accidental dismissal
          .onAppear {
            debugLog("🎵 MixerView: SoundSheet appeared for '\(sound.title)'")
          }
          .onDisappear {
            debugLog("🎵 MixerView: SoundSheet disappeared for '\(sound.title)'")
            // Trigger refresh when sound edit is closed in case sound properties changed
            soundsUpdateTrigger += 1
          }
      }
      .onChange(of: soundToEdit) { oldValue, newValue in
        if let sound = newValue {
          debugLog("🎵 MixerView: SoundSheet will be presented for '\(sound.title)'")
        } else if let oldSound = oldValue {
          debugLog("🎵 MixerView: SoundSheet will be dismissed for '\(oldSound.title)'")
        }
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
          // Trigger refresh when sound management is closed in case sounds were imported
          debugLog("🔄 MixerView: SoundManagementView closed, triggering refresh")
          soundsUpdateTrigger += 1
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .sheet(isPresented: $showingQuickMixEditor) {
        QuickMixEditorSheet()
      }
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
          .onDisappear {
            // Trigger refresh when preset edit is closed in case preset was modified
            debugLog("🔄 MixerView: EditPresetSheet closed, triggering refresh")
            soundsUpdateTrigger += 1

            // CRITICAL: Re-establish media controls after sheet dismissal
            // Animated artwork video preview may have caused iOS to disconnect remote command handlers
            // We restore controls regardless of play state since the gallery may have been browsed
            debugLog("🔄 MixerView: Restoring media controls after sheet dismissal")
            audioManager.setupMediaControls()
          }
      }
      .modifier(AudioErrorHandler())
      // Listen for changes that should trigger view updates
      .onChange(of: audioManager.sounds.count) { oldValue, newValue in
        // Sound imported or removed
        debugLog("🔄 MixerView: Sound count changed from \(oldValue) to \(newValue)")
        soundsUpdateTrigger += 1
      }
      .onChange(of: presetManager.currentPreset?.id) { oldValue, newValue in
        // Preset switched
        debugLog(
          "🔄 MixerView: Current preset changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")"
        )
        soundsUpdateTrigger += 1
      }
      .onChange(of: audioManager.isQuickMix) { _, isQuickMix in
        // Quick Mix is a grid-first mode — entering it (e.g. from the preset
        // picker) always lands on the mixer, never the Now Playing view.
        if isQuickMix { showingNowPlaying = false }
      }
      .onChange(of: presetManager.currentPreset?.soundStates.count) { oldValue, newValue in
        // Preset content changed (sounds added/removed)
        if let oldCount = oldValue, let newCount = newValue, oldCount != newCount {
          debugLog("🔄 MixerView: Preset sound count changed from \(oldCount) to \(newCount)")
          soundsUpdateTrigger += 1
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: Notification.Name("CustomSoundImported"))
      ) { _ in
        // Custom sound was imported
        debugLog("🔄 MixerView: Received CustomSoundImported notification")
        soundsUpdateTrigger += 1
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PresetUpdated"))) {
        _ in
        // Preset was updated
        debugLog("🔄 MixerView: Received PresetUpdated notification")
        soundsUpdateTrigger += 1
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
          backgroundImage: backgroundImage
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

    /// Mini player pinned above the bottom safe area; the zoom transition into
    /// the Now Playing cover originates from it.
    private var nowPlayingBar: some View {
      NowPlayingBar(expandPlayer: $showingNowPlaying)
        .matchedTransitionSource(id: "nowPlaying", in: nowPlayingNamespace)
        .padding(.horizontal, 16)
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

    @ViewBuilder
    private var mainContentView: some View {
      Group {
        if let soloSound = audioManager.soloModeSound, soundToEdit == nil,
          audioManager.previewModeSound == nil
        {
          // Solo mode view (only when no SoundSheet is presented and not in preview mode)
          soloModeView(for: soloSound)
            .onAppear {
              debugLog(
                "🎵 MixerView: Showing solo mode view for '\(soloSound.title)' (no SoundSheet open, no preview)"
              )
            }
        } else if let soloSound = audioManager.soloModeSound,
          soundToEdit != nil || audioManager.previewModeSound != nil
        {
          // Solo mode is active but SoundSheet is open or in preview mode, maintain normal layout
          Group {
            if audioManager.isQuickMix {
              QuickMixView()
            } else {
              soundsView
            }
          }
          .onAppear {
            if audioManager.previewModeSound != nil {
              debugLog(
                "🎵 MixerView: Solo mode active for '\(soloSound.title)' but preview mode active - maintaining normal layout"
              )
            } else {
              debugLog(
                "🎵 MixerView: Solo mode active for '\(soloSound.title)' but SoundSheet is open - maintaining normal layout"
              )
            }
          }
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
          soloMode: soundToEdit == nil && audioManager.previewModeSound == nil
            ? audioManager.soloModeSound?.id : nil,
          quickMix: audioManager.isQuickMix,
          listView: showingListView
        )
      )
      .onChange(of: audioManager.soloModeSound) { oldValue, newValue in
        if let newSolo = newValue {
          debugLog(
            "🎵 MixerView: Solo mode started for '\(newSolo.title)' (SoundSheet open: \(soundToEdit != nil))"
          )
        } else if let oldSolo = oldValue {
          debugLog(
            "🎵 MixerView: Solo mode ended for '\(oldSolo.title)' (SoundSheet open: \(soundToEdit != nil))"
          )
        }
      }
    }

    // MARK: - Helper Views

    // Helper computed properties are implemented in MixerView+UIComponents.swift
  }

  extension View {
    /// `safeAreaBar` keeps scroll edge effects correct under the mini player
    /// on iOS 26; earlier systems fall back to a plain safe-area inset.
    @ViewBuilder
    func nowPlayingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
      if #available(iOS 26.0, *) {
        safeAreaBar(edge: .bottom) { bar() }
      } else {
        safeAreaInset(edge: .bottom) { bar() }
      }
    }
  }

  #Preview("iPhone") {
    MixerView()
  }

  #Preview("iPad") {
    MixerView()
  }
#endif
