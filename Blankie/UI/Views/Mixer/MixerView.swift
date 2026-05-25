import SwiftUI
import TipKit

// Animation trigger struct to consolidate multiple animation values
private struct AnimationTrigger: Equatable {
  let soloMode: UUID?
  let quickMix: Bool
  let listView: Bool
}

#if os(iOS) || os(visionOS)
  struct MixerView: View {
    @StateObject var audioManager = AudioManager.shared
    @StateObject var globalSettings = GlobalSettings.shared
    @StateObject var presetManager = PresetManager.shared
    @StateObject var timerManager = TimerManager.shared
    @State var showingPresetPicker = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showingThemePicker = false
    @State var showingSoundManagement = false
    @State var showingSettings = false
    @State var showingQuickMixEditor = false
    @State var showingTimer = false
    @State var soundToEdit: Sound?
    @State var presetToEdit: Preset?
    @State var soundsUpdateTrigger = 0
    @State var playPauseTrigger = 0
    @State var menuTrigger = 0
    @State var showingNowPlaying = false
    @State private var isLandscape = false

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
      .sheet(isPresented: $showingPresetPicker) {
        PresetPickerView()
          .presentationDetents([.large])
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

      .sheet(isPresented: $showingThemePicker) {
        ThemePickerSheet(isPresented: $showingThemePicker)
      }
      .sheet(isPresented: $showingSoundManagement) {
        NavigationStack {
          SoundManagementView()
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
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
      .sheet(isPresented: $showingTimer) {
        TimerSheetView()
          .presentationDetents([.medium, .large])
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
          showingSettings: $showingSettings,
          showingPresetPicker: $showingPresetPicker
        )
      } detail: {
        NavigationStack {
          ZStack {
            if showingNowPlaying {
              NowPlayingSheet(
                onDismiss: {
                  withAnimation(.easeInOut(duration: 0.3)) {
                    showingNowPlaying = false
                  }
                },
                showingPresetPicker: $showingPresetPicker
              )
              .transition(.opacity)
            } else {
              ZStack {
                presetBackgroundView
                VStack(spacing: 0) {
                  mainContentView
                }
              }
              .transition(.opacity)
            }
          }
          .animation(.easeInOut(duration: 0.3), value: showingNowPlaying)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .principal) {
              Button {
                showingPresetPicker = true
              } label: {
                VStack(spacing: 0) {
                  HStack(spacing: 4) {
                    Text(navigationTitle)
                      .font(.headline)
                      .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                      .font(.caption2.weight(.semibold))
                      .foregroundColor(.secondary)
                  }
                  if let caption = topBarCaption {
                    Text(caption)
                      .font(.caption2)
                      .foregroundColor(.secondary)
                  }
                }
              }
              .sensoryFeedback(.selection, trigger: showingPresetPicker)
            }

            // Edit button is only meaningful on the grid/list view — hide it
            // while Now Playing is showing so it doesn't compete with the
            // NowPlayingSheet chrome.
            ToolbarItem(placement: .confirmationAction) {
              if !showingNowPlaying {
                if audioManager.isQuickMix {
                  Button {
                    showingQuickMixEditor = true
                  } label: {
                    Image(systemName: "slider.vertical.3")
                      .font(.system(size: 18))
                      .foregroundColor(.secondary)
                  }
                  .accessibilityLabel("Edit Quick Mix")
                } else if let currentPreset = presetManager.currentPreset {
                  Button {
                    presetToEdit = currentPreset
                  } label: {
                    Image(systemName: "slider.vertical.3")
                      .font(.system(size: 18))
                      .foregroundColor(.secondary)
                  }
                  .accessibilityLabel("Edit Preset")
                }
              }
            }
          }
          .toolbarBackground(.hidden, for: .navigationBar)
          // Playback controls must be reachable at every size class. Without
          // this, iPad at regular horizontal size shows no play/pause at all
          // (compact width falls back to iPhoneLayout, which does include it).
          .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomToolbar
          }
        }
      }
      .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var iPhoneLayout: some View {
      NavigationStack {
        ZStack {
          if showingNowPlaying {
            NowPlayingSheet(
              onDismiss: {
                withAnimation(.easeInOut(duration: 0.3)) {
                  showingNowPlaying = false
                }
              },
              showingPresetPicker: $showingPresetPicker
            )
            .transition(.opacity)
          } else {
            ZStack {
              presetBackgroundView
              VStack(spacing: 0) {
                mainContentView
              }
            }
            .transition(.opacity)
          }
        }
        .onGeometryChange(for: Bool.self) { geo in
          geo.size.width > geo.size.height
        } action: { newValue in
          isLandscape = newValue
        }
        .safeAreaInset(edge: .top) {
          VStack(spacing: 0) {
            // Tappable preset title
            Button {
              showingPresetPicker = true
            } label: {
              HStack(spacing: 4) {
                Text(navigationTitle)
                  .font(showingNowPlaying ? .title3.weight(.semibold) : .headline)
                  .foregroundColor(showingNowPlaying ? .white : .primary)
                Image(systemName: "chevron.down")
                  .font(
                    showingNowPlaying ? .caption.weight(.semibold) : .caption2.weight(.semibold)
                  )
                  .foregroundColor(showingNowPlaying ? .white.opacity(0.5) : .secondary)
              }
              .padding(.vertical, 6)
            }
            .sensoryFeedback(.selection, trigger: showingPresetPicker)

            if let caption = topBarCaption {
              Text(caption)
                .font(.caption2)
                .foregroundColor(showingNowPlaying ? .white.opacity(0.6) : .secondary)
            }
          }
          .padding(.top, showingNowPlaying && isLandscape ? 8 : 0)
          .padding(.bottom, 8)
          .frame(maxWidth: .infinity)
          .background {
            if !showingNowPlaying {
              Rectangle().fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: [.top, .horizontal])
            }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if showingNowPlaying && isLandscape {
            HStack(spacing: 0) {
              Spacer()
                .frame(maxWidth: .infinity)
              bottomToolbar
                .frame(maxWidth: .infinity)
            }
          } else {
            bottomToolbar
          }
        }
        .animation(.easeInOut(duration: 0.3), value: showingNowPlaying)
        .navigationBarHidden(true)
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

    private var timerTopBarText: String {
      if timerManager.remainingTime < 60 {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.second]
        return "Stops in \(formatter.string(from: timerManager.remainingTime) ?? "0 seconds")"
      } else {
        let endTime = Date().addingTimeInterval(timerManager.remainingTime)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Stops at \(formatter.string(from: endTime))"
      }
    }

    /// Small status line rendered under the preset name in the top bar.
    /// "Paused" takes priority so users always know the global state; the
    /// timer caption only shows while actively playing.
    var topBarCaption: String? {
      if !audioManager.isGloballyPlaying && audioManager.hasSelectedSounds {
        return String(localized: "Paused", comment: "Top bar caption when playback is paused")
      }
      if timerManager.isTimerActive {
        return timerTopBarText
      }
      return nil
    }
  }

  extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
      if condition {
        transform(self)
      } else {
        self
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
