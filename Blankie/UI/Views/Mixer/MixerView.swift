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
    @StateObject var onboardingManager = OnboardingManager.shared
    @State var showingListView = false
    @State var showingPresetPicker = false
    @State var showingOnboarding = false
    @State var hideInactiveSounds = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State var draggedIndex: Int?
    @State var hoveredIndex: Int?
    @State var dragResetTimer: Timer?
    @State private var showingThemePicker = false
    @State var showingSoundManagement = false
    @State var showingSettings = false
    @State var showingQuickMixEditor = false
    @State var showingViewSettings = false
    @State var showingTimer = false
    @State var soundToEdit: Sound?
    @State var presetToEdit: Preset?
    @State var soundsUpdateTrigger = 0
    @State var editMode: EditMode = .inactive
    @State var playPauseTrigger = 0
    @State var menuTrigger = 0
    @State var showingNowPlaying = false

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
          .interactiveDismissDisabled() // Prevent accidental dismissal
          .onAppear {
            print("🎵 MixerView: SoundSheet appeared for '\(sound.title)'")
          }
          .onDisappear {
            print("🎵 MixerView: SoundSheet disappeared for '\(sound.title)'")
            // Trigger refresh when sound edit is closed in case sound properties changed
            soundsUpdateTrigger += 1
          }
      }
      .onChange(of: soundToEdit) { oldValue, newValue in
        if let sound = newValue {
          print("🎵 MixerView: SoundSheet will be presented for '\(sound.title)'")
        } else if let oldSound = oldValue {
          print("🎵 MixerView: SoundSheet will be dismissed for '\(oldSound.title)'")
        }
      }

      .sheet(isPresented: $showingViewSettings) {
        ViewSettingsSheet(
          isPresented: $showingViewSettings,
          showingListView: $showingListView,
          hideInactiveSounds: $hideInactiveSounds
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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
          print("🔄 MixerView: SoundManagementView closed, triggering refresh")
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
            print("🔄 MixerView: EditPresetSheet closed, triggering refresh")
            soundsUpdateTrigger += 1

            // CRITICAL: Re-establish media controls after sheet dismissal
            // Animated artwork video preview may have caused iOS to disconnect remote command handlers
            // We restore controls regardless of play state since the gallery may have been browsed
            print("🔄 MixerView: Restoring media controls after sheet dismissal")
            audioManager.setupMediaControls()
          }
      }
      .modifier(AudioErrorHandler())
      // Listen for changes that should trigger view updates
      .onChange(of: audioManager.sounds.count) { oldValue, newValue in
        // Sound imported or removed
        print("🔄 MixerView: Sound count changed from \(oldValue) to \(newValue)")
        soundsUpdateTrigger += 1
      }
      .onChange(of: presetManager.currentPreset?.id) { oldValue, newValue in
        // Preset switched
        print("🔄 MixerView: Current preset changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")")
        soundsUpdateTrigger += 1
      }
      .onChange(of: presetManager.currentPreset?.soundStates.count) { oldValue, newValue in
        // Preset content changed (sounds added/removed)
        if let oldCount = oldValue, let newCount = newValue, oldCount != newCount {
          print("🔄 MixerView: Preset sound count changed from \(oldCount) to \(newCount)")
          soundsUpdateTrigger += 1
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CustomSoundImported"))) { _ in
        // Custom sound was imported
        print("🔄 MixerView: Received CustomSoundImported notification")
        soundsUpdateTrigger += 1
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PresetUpdated"))) { _ in
        // Preset was updated
        print("🔄 MixerView: Received PresetUpdated notification")
        soundsUpdateTrigger += 1
      }
      .task {
        // Check if we should show onboarding after a brief delay
        try? await Task.sleep(for: .seconds(1))
        if onboardingManager.checkAndShowOnboarding(hasCustomPresets: presetManager.hasCustomPresets) {
          showingOnboarding = true
        }
      }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var iPadLayout: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarContentView(
          showingAbout: .constant(false),
          showingSoundManagement: $showingSoundManagement
        )
      } detail: {
        NavigationStack {
          ZStack {
            presetBackgroundView
            VStack(spacing: 0) {
              mainContentView
            }
          }
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .principal) {
              Text(navigationTitle)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.primary)
            }

            ToolbarItem(placement: .confirmationAction) {
              // Preset edit button (right aligned) - also show for default preset
              if let currentPreset = presetManager.currentPreset,
                 !audioManager.isQuickMix
              {
                Button {
                  presetToEdit = currentPreset
                } label: {
                  Image(systemName: "slider.vertical.3")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                }
              }
            }
          }
          .toolbarBackground(.hidden, for: .navigationBar)
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
        .safeAreaInset(edge: .top) {
          VStack(spacing: 0) {
            // Tappable preset title
            Button {
              showingPresetPicker = true
            } label: {
              HStack(spacing: 4) {
                Text(navigationTitle)
                  .font(.headline)
                  .foregroundColor(showingNowPlaying ? .white : .primary)
                Image(systemName: "chevron.down")
                  .font(.caption2.weight(.semibold))
                  .foregroundColor(showingNowPlaying ? .white.opacity(0.5) : .secondary)
              }
              .padding(.vertical, 6)
            }
            .sensoryFeedback(.selection, trigger: showingPresetPicker)

            if timerManager.isTimerActive {
              Text(timerTopBarText)
                .font(.caption2)
                .foregroundColor(showingNowPlaying ? .white.opacity(0.6) : .secondary)
            }
          }
          .padding(.bottom, 8)
          .frame(maxWidth: .infinity)
          .background {
            if !showingNowPlaying {
              Rectangle().fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
            }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          bottomToolbar
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
              print(
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
              listView
            }
          }
          .onAppear {
            if audioManager.previewModeSound != nil {
              print(
                "🎵 MixerView: Solo mode active for '\(soloSound.title)' but preview mode active - maintaining normal layout"
              )
            } else {
              print(
                "🎵 MixerView: Solo mode active for '\(soloSound.title)' but SoundSheet is open - maintaining normal layout"
              )
            }
          }
        } else if audioManager.isQuickMix {
          // Quick Mix mode view
          QuickMixView()
        } else {
          // List view
          listView
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
          print(
            "🎵 MixerView: Solo mode started for '\(newSolo.title)' (SoundSheet open: \(soundToEdit != nil))"
          )
        } else if let oldSolo = oldValue {
          print(
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
