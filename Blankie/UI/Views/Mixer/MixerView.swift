//
//  MixerView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI
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
    @State private var timerManager = TimerManager.shared
    @ObservedObject private var appState = AppState.shared
    /// iPhone navigation path. The Library is the stack's root and the app
    /// launches with the mixer pushed on top, so the mixer's back button (or
    /// an edge swipe) leads left to the Library.
    @State private var iPhonePath: [IPhonePage] = [.mixer]
    // Start with the Library showing; the system still collapses it when narrow.
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
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
    /// iPhone: the Sound Mixer sheet the floating bar opens over Now Playing.
    @State private var showingMixerSheet = false
    /// The mixer sheet was asked to close while an editor sat on it; it closes
    /// once that editor does, so the editor's unsaved draft isn't thrown away.
    @State private var closesMixerSheetAfterEditor = false
    @State private var showingPageTimer = false
    /// iPhone Duo's cover keeps a vertical toolbar rail beside the page; the
    /// player's AirPlay and Timer move onto it.
    @State private var hasToolbarRail = false
    @State private var showingVolumeZeroWarning = false
    @State private var isLandscape = false
    // Measured Now Playing bar height, used to inset the iPhone and stacked Duo
    // Library lists under it (the stack's safeAreaBar doesn't reach that root list).
    @State private var nowPlayingBarHeight: CGFloat = 0
    /// The fold in window space (decides the propped-up layout) and in the
    /// playback bar's space (keeps the bar off a bent crease).
    @State private var windowFold = FoldInfo.none
    @State private var barFold = FoldInfo.none
    @State private var barWidth: CGFloat = 0
    /// Nightstand: the lower half can swap the sounds for the Library, and an
    /// open Now Playing steps aside while propped up (restored after).
    @State private var proppedShowsLibrary = false
    @State private var quickMixShowsColumn = false
    @State private var detailFold = FoldInfo.none
    @State private var detailWidth: CGFloat = 0
    @State private var nowPlayingBeforeProppedUp = false
    @State private var proppedLowerHeight: CGFloat = 0
    @State private var proppedBottomInset: CGFloat = 0
    /// Anchors the zoom transition between the mini bar and the Now Playing cover.
    @Namespace private var nowPlayingNamespace

    // Performance optimization: cached state properties
    @State var cachedFilteredSounds: [Sound] = []
    @State var lastFilterHash: Int = 0
    @State var cachedColumnWidth: CGFloat = 0
    @State var lastScreenWidth: CGFloat = 0
    @State var backgroundImage: PlatformImage?

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
      editorPresentations(layoutBody, hosts: !showingMixerSheet)
        #if os(iOS)
          // The portrait lock depends on the size classes, so iOS has to re-ask
          // when iPhone Duo opens or closes.
          .onChange(of: [horizontalSizeClass, verticalSizeClass]) {
            IOSAppDelegate.refreshSupportedOrientations()
          }
        #endif
    }

    private var layoutBody: some View {
      Group {
        switch currentLayout {
        case .compact:
          iPhoneLayout
        case .regular:
          regularLayout
        case .proppedUp:
          proppedUpLayout
        case .pages:
          pagesLayout
        }
      }
      .onFoldChange { windowFold = $0 }
      // iPad covers the content with a fullScreenCover; even a page-sized sheet
      // stays an inset floating card there. iPhone keeps a sheet for the
      // system's grab-anywhere pull-to-dismiss. Both zoom from the mini player.
      // Swapping the two rebuilds everything above, so the layout handlers
      // below stay outside it.
      .modifier(
        NowPlayingPresentation(
          isPresented: $showingNowPlaying,
          coversFullScreen: isLargeDevice,
          namespace: nowPlayingNamespace
        ) {
          NowPlayingSheet(
            onDismiss: { showingNowPlaying = false },
            backgroundImage: backgroundImage,
            onNavigateToSolo: { swapNowPlaying(showSheet: false) },
            soundsPanel: AnyView(nowPlayingSoundsPanel)
          )
        }
      )
      // The iPhone's player is a page and its mixer a sheet; the wide layouts
      // flip that. Hand Now Playing over when the layout changes (closing or
      // opening iPhone Duo) instead of stacking a sheet over the page.
      .onChange(of: currentLayout == .compact) { _, compact in
        if compact {
          if showingNowPlaying && opensNowPlaying {
            showingNowPlaying = false
            iPhonePath = [.mixer]
          }
        } else {
          closeMixerSheet()
        }
      }
      // A solo sound has nothing to mix: close a mixer left open for a preset.
      .onChange(of: audioManager.soloModeSound != nil) { _, solo in
        if solo { closeMixerSheet() }
      }
      .onChange(of: editorIsOpen) { _, open in
        if !open, closesMixerSheetAfterEditor {
          closesMixerSheetAfterEditor = false
          showingMixerSheet = false
        }
      }
      .onChange(of: showingMixerSheet) { _, showing in
        if !showing { closesMixerSheetAfterEditor = false }
      }
      .sheet(isPresented: $showingMixerSheet) {
        mixerSheet
          .presentationSizing(.page)
          .presentationDragIndicator(.hidden)
      }
      .onChange(of: currentLayout == .proppedUp) { _, proppedUp in
        if proppedUp {
          nowPlayingBeforeProppedUp = showingNowPlaying
          showingNowPlaying = false
        } else if nowPlayingBeforeProppedUp {
          nowPlayingBeforeProppedUp = false
          // Shut straight from seated: the iPhone's Now Playing is its page, so
          // restore that rather than a sheet over it.
          if currentLayout == .compact && opensNowPlaying {
            iPhonePath = [.mixer]
          } else if currentLayout != .pages {
            showingNowPlaying = true
          }
        }
      }
      // Facing pages already show Now Playing on the left page; close a player
      // the closed phone left open (Quick Mix, or a mixer-first preset).
      .onChange(of: currentLayout == .pages) { _, pages in
        if pages { showingNowPlaying = false }
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
      // The last preset couldn't be restored at launch: open on the Library to
      // choose one, not a player for a preset nobody picked.
      // Initial too: a launch from CarPlay or a widget can finish loading
      // before this view exists.
      .onChange(of: presetManager.isLoading, initial: true) { _, loading in
        guard !loading, presetManager.lastPresetRestoreFailed else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { iPhonePath = [] }
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
        .presentationSizing(.page)
        .onDisappear {
          Logger.ui.debug("MixerView: SoundManagementView closed")
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
          // A full settings screen, not a dialog — give it a page on iPad
          // instead of the default small centered form sheet.
          .presentationSizing(.page)
      }
      // Sound add/remove, preset switches, and preset edits all flow through
      // @Observable reads now (audioManager.sounds, presetManager.currentPreset),
      // so the grid refreshes automatically — no manual trigger needed. Only the
      // Quick Mix transition keeps a handler, since it has navigation side effects.
      .onChange(of: audioManager.isQuickMix) { _, isQuickMix in
        // Quick Mix is a grid-first mode — entering it (e.g. from the preset
        // picker) always lands on the mixer, never the Now Playing view.
        // The mixer sheet shows the preset's sounds; started from outside
        // (widget, CarPlay, Siri), Quick Mix closes it too.
        if isQuickMix {
          showingNowPlaying = false
          closeMixerSheet()
        }
      }
    }

    /// Any editor or panel that the mixer sheet may be hosting.
    private var editorIsOpen: Bool {
      soundToEdit != nil || presetToEdit != nil || showingQuickMixEditor
        || showingSpatialMixer || showingNewPresetSheet || showingPageTimer
        || showingNewPresetConfirmation
    }

    /// Closes the mixer sheet from code (a layout change, solo, Quick Mix),
    /// waiting for an editor on it to close first.
    private func closeMixerSheet() {
      guard showingMixerSheet else { return }
      if editorIsOpen {
        closesMixerSheetAfterEditor = true
      } else {
        showingMixerSheet = false
      }
    }

    /// The editors the mixer's Edit/Spatial buttons open, plus the audio error
    /// alert. Attached twice — the root and the iPhone's Sound Mixer sheet — and
    /// only the one in front hosts, since a view already showing a sheet can't
    /// present another.
    private func editorPresentations(_ content: some View, hosts: Bool) -> some View {
      content
        .modifier(AudioErrorHandler(hosts: hosts))
        .sheet(item: gated($soundToEdit, hosts)) { sound in
          SoundSheet(mode: .edit(sound))
            .modifier(EditorPlacement(layout: currentLayout))
            .interactiveDismissDisabled()  // Prevent accidental dismissal
            .onAppear {
              Logger.ui.debug("MixerView: SoundSheet appeared for '\(sound.title)'")
            }
            .onDisappear {
              Logger.ui.debug("MixerView: SoundSheet disappeared for '\(sound.title)'")
            }
        }
        .sheet(isPresented: gated($showingQuickMixEditor, hosts)) {
          QuickMixEditorSheet()
            .modifier(EditorPlacement(layout: currentLayout))
            .presentationSizing(.page)
        }
        .sheet(isPresented: gated($showingSpatialMixer, hosts)) {
          SpatialMixerView()
        }
        .sheet(isPresented: gated($showingPageTimer, hosts)) {
          TimerSheetView()
            .presentationDetents([.medium, .large])
        }
        // The default preset has no editor; its Edit slot offers to start a new
        // preset from whatever is currently playing instead.
        .alert(
          "Create a Preset from Playing Sounds?",
          isPresented: gated($showingNewPresetConfirmation, hosts)
        ) {
          Button("Cancel", role: .cancel) {}
          Button("Create") { showingNewPresetSheet = true }
        } message: {
          Text("The default preset can't be edited. Start a new preset with your current sounds.")
        }
        .sheet(isPresented: gated($showingNewPresetSheet, hosts)) {
          CreatePresetSheet(
            isPresented: $showingNewPresetSheet,
            initialSelectedSounds: Set(audioManager.sounds.filter { $0.isSelected }.map(\.fileName))
          )
        }
        .sheet(item: gated($presetToEdit, hosts)) { preset in
          EditPresetSheet(preset: preset, isPresented: $presetToEdit)
            .modifier(EditorPlacement(layout: currentLayout))
            .onDisappear {
              Logger.ui.debug("MixerView: EditPresetSheet closed")

              // CRITICAL: Re-establish media controls after sheet dismissal
              // Animated artwork video preview may have caused iOS to disconnect remote command handlers
              // We restore controls regardless of play state since the gallery may have been browsed
              Logger.ui.debug("MixerView: Restoring media controls after sheet dismissal")
              audioManager.setupMediaControls()
            }
        }
    }

    private func gated<Item>(_ binding: Binding<Item?>, _ hosts: Bool) -> Binding<Item?> {
      Binding(get: { hosts ? binding.wrappedValue : nil }, set: { binding.wrappedValue = $0 })
    }

    private func gated(_ binding: Binding<Bool>, _ hosts: Bool) -> Binding<Bool> {
      Binding(get: { hosts && binding.wrappedValue }, set: { binding.wrappedValue = $0 })
    }

    /// App-wide Grid/List preference. Read live from GlobalSettings so changes
    /// made in the Settings sheet take effect immediately — a local @State
    /// mirror would only refresh on the next view appearance.
    var showingListView: Bool {
      globalSettings.showingListView
    }

    // MARK: - Layouts

    @ViewBuilder
    private var regularLayout: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarContentView(
          showingSettings: $showingSettings
        )
      } detail: {
        NavigationStack {
          ZStack {
            presetBackgroundView
            VStack(spacing: 0) {
              if showsRegularHeader {
                presetPageHeader
              }
              mainContentView
            }
            // Beside the Library on a flat iPhone Duo, the mixer takes the page
            // past the fold, where the book pose puts it, so bending moves nothing.
            .padding(
              .leading,
              CreaseInsets.trailingPageStart(containerWidth: detailWidth, fold: detailFold) ?? 0)
          }
          .onFoldChange { detailFold = $0 }
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: {
            detailWidth = $0
          }
          // The page header (or Quick Mix's control column) names what's
          // playing; otherwise a plain inline title.
          .navigationTitle(
            regularTitle
          )
          .navigationBarTitleDisplayMode(.inline)
          // The NavigationSplitView owns the sidebar toggle and keeps it
          // available in the detail when collapsed, so we add no reveal control.
          .toolbarBackground(.hidden, for: .navigationBar)
          .toolbar {
            editToolbarItems
          }
        }
        // Playback controls must be reachable at every size class. Without
        // this, iPad at regular horizontal size shows no play/pause at all
        // (compact width falls back to iPhoneLayout, which does include it).
        // Quick Mix carries its own controls; elsewhere a bare bar (the sidebar
        // and header already say what's playing).
        .nowPlayingBottomBar {
          if !hidesNowPlayingBarForSolo && !audioManager.isQuickMix {
            regularPlaybackBar
          }
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
          bottomBarHeight: nowPlayingBarHeight
        )
        .navigationDestination(for: IPhonePage.self) { _ in
          // Quick Mix is mixer-only; everything else plays on Now Playing
          // unless someone chose the mixer first in Settings.
          if opensNowPlaying {
            nowPlayingPage(drawsBackdrop: true, showsMixerButton: true)
          } else {
            mixerPage
          }
        }
      }
      // Attached to the stack, not a page, so the bar persists across the
      // Library root and the pushed mixer.
      .nowPlayingBottomBar {
        if !hidesNowPlayingBarForSolo {
          nowPlayingBar
        }
      }
    }

    /// On the iPhone stack's Library root, the bar tap steps "in" to the mixer
    /// instead of expanding the player (Library → mixer → full player); from
    /// the mixer — and always on iPad, where the mixer is the ever-present
    /// detail — it expands Now Playing.
    private var barShowsMixer: Bool {
      !isLargeDevice && iPhonePath.isEmpty
    }

    /// Hide the bottom mini player while the mixer is showing the big solo card
    /// — the card already is the now-playing surface, so the bar would just echo
    /// the same sound. It stays everywhere else: the iPhone Library root
    /// (`barShowsMixer`), Quick Mix, and normal preset playback.
    private var hidesNowPlayingBarForSolo: Bool {
      // The iPhone's Now Playing page is the player itself; its toolbar holds
      // Timer, AirPlay and the Sound Mixer. The Library keeps its bar.
      if onPhonePlayerPage { return true }
      return soloLayoutSound != nil && !barShowsMixer
    }

    /// iPhone pages open to Now Playing. Sounds always do; presets do unless
    /// the mixer is chosen first in Settings. Quick Mix is mixer-only.
    private var opensNowPlaying: Bool {
      !audioManager.isQuickMix
        && (globalSettings.nowPlayingFirst || audioManager.soloModeSound != nil)
    }

    private var onPhonePlayerPage: Bool {
      !isLargeDevice && !iPhonePath.isEmpty && opensNowPlaying
    }

    /// Cross between a solo sound (inline player) and a preset (modal sheet) via
    /// next/previous. The two layouts are lined up, so swap instantly (no zoom or
    /// slide) — it reads as the content simply changing rather than a full sheet
    /// present/dismiss. When returning to a solo sound, make the mixer the page
    /// behind the sheet so it lands on the solo sound's inline page.
    private func swapNowPlaying(showSheet: Bool) {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        if !showSheet { iPhonePath = [.mixer] }
        showingNowPlaying = showSheet
      }
    }

    /// Mini player pinned above the bottom safe area; the zoom transition into
    /// the Now Playing cover originates from it.
    private var nowPlayingBar: some View {
      NowPlayingBar(showsMixer: barShowsMixer && !opensNowPlaying) {
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

    private var currentLayout: MixerLayout {
      MixerLayout.resolve(isRegularWidth: isLargeDevice, fold: windowFold)
    }

    // MARK: - Facing pages (iPhone Duo open)

    /// Two pages split at the fold. With the Library open (left), Now Playing
    /// takes the right page. Choosing something puts its Now Playing on the left
    /// and the mixer on the right; a solo sound has nothing to mix, so its Now
    /// Playing spreads across both pages.
    private var pagesLayout: some View {
      GeometryReader { proxy in
        let split = CreaseInsets.split(containerWidth: proxy.size.width, fold: windowFold)
        let libraryOpen = iPhonePath.isEmpty
        let spreads = audioManager.soloModeSound != nil && !libraryOpen
        ZStack {
          presetBackgroundView
          // Now Playing beside the Library has no system slider of its own.
          volumeHUDSuppressor
          HStack(spacing: 0) {
            pagesPlayer(spreads: spreads)
              .frame(width: spreads ? proxy.size.width : split.leading)
            if !spreads {
              Color.clear
                .frame(width: split.gap)
              if libraryOpen {
                // Opening the mixer closes the Library: Now Playing moves left
                // and the mixer takes this page.
                NowPlayingSheet(
                  backgroundImage: backgroundImage, inline: true, showsActions: false,
                  onOpenMixer: { iPhonePath = [.mixer] }, actionRowIncludesAirPlay: true
                )
                .environment(\.horizontalSizeClass, .compact)
              } else {
                pagesMixer
              }
            }
          }
        }
      }
    }

    private func pagesPlayer(spreads: Bool) -> some View {
      NavigationStack(path: $iPhonePath) {
        LibraryView(
          presentation: .page,
          onOpenSettings: { showingSettings = true },
          onSelection: { iPhonePath = [.mixer] },
          // Now Playing is on the other page, so there's no mini player.
          bottomBarHeight: 0
        )
        .navigationDestination(for: IPhonePage.self) { _ in
          nowPlayingPage(drawsBackdrop: false, spreads: spreads)
            .containerBackground(.clear, for: .navigation)
        }
      }
      .environment(\.horizontalSizeClass, .compact)
    }

    private var pagesMixer: some View {
      NavigationStack {
        Group {
          if audioManager.isQuickMix {
            QuickMixView()
          } else {
            soundsView
          }
        }
        .containerBackground(.clear, for: .navigation)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          playerToolbarItems(showsTimer: true)
          editToolbarItems
        }
      }
      .environment(\.horizontalSizeClass, .compact)
    }

    // MARK: - Nightstand (propped up, partly folded)

    /// Apple's one sanctioned pose layout: the upright half shows what's
    /// playing, the flat half holds the sounds and every control.
    private var proppedUpLayout: some View {
      let showsLibrary = proppedShowsLibrary || soloLayoutSound != nil
      return ZStack(alignment: .top) {
        presetBackgroundView
        volumeHUDSuppressor
        VStack(spacing: 0) {
          // Held open flat, the Library takes the whole screen; only seated
          // does it share the screen with what's playing.
          if showsLibrary && !windowFold.isActive {
            proppedUpLibrary
          } else {
            NowPlayingSheet(backgroundImage: backgroundImage, inline: true, displayOnly: true)
              .frame(height: max(windowFold.frame.minY, 0))
            Color.clear
              .frame(height: windowFold.frame.height)
            // Two rows exactly fill the flat half: 16 pt top, gap and bottom.
            proppedUpLower
              .environment(\.soundTileHeight, max((proppedLowerHeight - 48) / 2, 100))
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .onGeometryChange(for: CGFloat.self) {
                $0.size.height
              } action: {
                proppedLowerHeight = $0
              }
              // Held flat, tiles fade out across the fold as they scroll up
              // instead of vanishing at its edge.
              .scrollClipDisabled(!windowFold.isActive)
              .mask(alignment: .top) {
                let bleed = windowFold.isActive ? 0 : windowFold.frame.height + 32
                VStack(spacing: 0) {
                  LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: bleed)
                  Color.black
                }
                .padding(.top, -bleed)
              }
          }
        }
      }
      // Floats over the content like the iPhone bar, so the Library keeps its
      // background behind it and scrolls under it. Inset from the sides as far
      // as from the bottom edge, so it sits evenly in the rounded corners.
      .nowPlayingBottomBar {
        proppedUpBar
          .padding(.horizontal, max(proppedBottomInset, 16))
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            nowPlayingBarHeight = $0
          }
      }
      .onGeometryChange(for: CGFloat.self) {
        $0.safeAreaInsets.bottom
      } action: {
        proppedBottomInset = $0
      }
    }

    private var proppedUpLibrary: some View {
      NavigationStack {
        LibraryView(
          presentation: .page,
          onOpenSettings: { showingSettings = true },
          onSelection: { proppedShowsLibrary = false },
          bottomBarHeight: nowPlayingBarHeight
        )
      }
    }

    @ViewBuilder
    private var proppedUpLower: some View {
      if proppedShowsLibrary || soloLayoutSound != nil {
        proppedUpLibrary
      } else if audioManager.isQuickMix {
        QuickMixView(columns: 4)
      } else {
        SoundGridView(sounds: filteredSounds, onMove: moveItems, columns: 4)
      }
    }

    private var proppedUpBar: some View {
      HStack(spacing: 8) {
        if soloLayoutSound == nil {
          Button {
            proppedShowsLibrary.toggle()
          } label: {
            Label(
              proppedShowsLibrary ? "Sounds" : "Library",
              systemImage: proppedShowsLibrary ? "square.grid.2x2" : "chevron.backward"
            )
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
          }
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
          .tint(.primary)
        }
        // A popover between the fold and the bar, not a sheet over both halves.
        NowPlayingBar(style: .bare, showsExpand: false, timerAsPopover: true) {}
        if globalSettings.enableSpatialAudio, soloLayoutSound == nil, !audioManager.isQuickMix {
          Button {
            showingSpatialMixer = true
          } label: {
            Label("Spatial Mix", systemImage: "speaker.wave.1.arrowtriangles.up.right.down.left")
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
          .tint(.primary)
        }
        // Disabled rather than removed when there's nothing to edit, like the toolbar.
        let target = editTarget
        Button {
          target?.action()
        } label: {
          Label(
            LocalizedStringKey(target?.label ?? "Edit Preset"),
            systemImage: target?.icon ?? "slider.vertical.3"
          )
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .disabled(target == nil)
      }
      // Same cap as the Now Playing bar, so the circle buttons' symbols fit.
      .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    /// With a fold, flat or bent, the bar keeps to one page instead of spanning
    /// it: past the fold beside the Library, otherwise the leading page.
    private var regularPlaybackBar: some View {
      let start = CreaseInsets.trailingPageStart(containerWidth: barWidth, fold: barFold)
      let page =
        start == nil ? CreaseInsets.leadingPage(containerWidth: barWidth, fold: barFold) : nil
      return NowPlayingBar(style: .bare) {
        showingNowPlaying = true
      }
      .matchedTransitionSource(id: "nowPlaying", in: nowPlayingNamespace)
      .padding(.leading, (start ?? 0) + 16)
      .padding(.trailing, page.map { barWidth - $0 + 16 } ?? 16)
      .onFoldChange { barFold = $0 }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        barWidth = $0
      }
    }

    /// iPhone: what's playing is the page. Timer sits in the nav bar; the
    /// floating bar below opens the mixer, which carries the edit controls.
    /// - Parameter showsMixerButton: iPhone, where the mixer opens as a sheet;
    ///   the open Duo already shows it on the other page.
    private func nowPlayingPage(
      drawsBackdrop: Bool, showsMixerButton: Bool = false, spreads: Bool = false
    ) -> some View {
      ZStack {
        if drawsBackdrop { presetBackgroundView }
        // While mixing with other audio the player's own slider isn't the
        // system's, so nothing else here keeps the HUD away.
        volumeHUDSuppressor
        // Until the launch restore lands, the player would show "Blankie" and
        // then slide to the real preset; show nothing, like the mixer page.
        if !presetManager.isLoading {
          NowPlayingSheet(
            backgroundImage: backgroundImage, inline: true,
            // Mixer-first presets: leaving a solo sound for a preset lands on its
            // mixer with Now Playing over it, as before.
            // Only the iPhone opens a cover for it; the open Duo already shows the
            // preset's Now Playing on its page.
            onNavigateToPreset: globalSettings.nowPlayingFirst || currentLayout != .compact
              ? nil : { swapNowPlaying(showSheet: true) },
            showsActions: false,
            spreadsAcrossFold: spreads,
            onOpenMixer: showsMixerButton ? { showingMixerSheet = true } : nil,
            actionRowIncludesAirPlay: !hasToolbarRail,
            actionRowIncludesTimer: !hasToolbarRail,
            favoriteInToolbar: hasToolbarRail
          )
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .modifier(ToolbarRailReader(isActive: $hasToolbarRail))
      .onGeometryChange(for: Bool.self) { geo in
        geo.size.width > geo.size.height
      } action: { newValue in
        isLandscape = newValue
      }
      .toolbar {
        // Beside the open Duo's mixer page, AirPlay, Timer and the editors live
        // in that page's bar instead.
        if spreads {
          playerToolbarItems(showsTimer: true)
        }
        // On the Duo's cover the favorite star, AirPlay and Timer move onto the
        // rail under Back; the Sound Mixer button stays in the player.
        if showsMixerButton, hasToolbarRail, !spreads {
          playerToolbarItems(showsTimer: true, showsFavorite: true)
        }
        // iPhone keeps AirPlay and Timer in the player's row beside the mixer.
        if showsMixerButton || spreads {
          editToolbarItems
        }
      }
    }

    /// AirPlay, then Timer (unless the player shows it beside the Sound Mixer),
    /// kept in the side bar under Back on iPhone Duo; AirPlay's custom picker
    /// would otherwise pull them into a horizontal bar.
    @ToolbarContentBuilder
    private func playerToolbarItems(showsTimer: Bool, showsFavorite: Bool = false)
      -> some ToolbarContent
    {
      verticalPreferred(
        ToolbarItemGroup(placement: .topBarTrailing) {
          // Quick Mix can't be a favorite; everything else stars under its token.
          if showsFavorite, !audioManager.isQuickMix,
            let token = audioManager.currentFavoriteToken
          {
            let starred = globalSettings.isStarred(token)
            Button {
              globalSettings.toggleStarred(token)
            } label: {
              Label(
                starred ? "Unfavorite" : "Favorite",
                systemImage: starred ? "star.fill" : "star")
            }
            .tint(starred ? accent : .primary)
          }

          AirPlayRouteButton(activeColor: accent, inactiveColor: .primary)
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text("AirPlay"))
            // The side bar drops this custom view when iPhone Duo's cover turns;
            // a fresh one per orientation keeps it.
            .id(isLandscape)

          if showsTimer {
            Button {
              showingPageTimer = true
            } label: {
              Label("Timer", systemImage: "timer")
            }
            .tint(timerManager.isTimerActive ? accent : .primary)
          }
        })

    }

    @ToolbarContentBuilder
    private func verticalPreferred(_ content: some ToolbarContent) -> some ToolbarContent {
      #if os(iOS)
        if #available(iOS 27.1, *) {
          content.axisBehavior(.verticalPreferred)
        } else {
          content
        }
      #else
        content
      #endif
    }

    /// iPhone: the mixer in the sheet Now Playing uses on wide screens.
    private var mixerSheet: some View {
      editorPresentations(
        NavigationStack {
          ZStack {
            presetBackgroundView
            soundsView
          }
          .navigationTitle("Sound Mixer")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                showingMixerSheet = false
              } label: {
                Label("Close", systemImage: "chevron.down")
              }
              .tint(.primary)
            }
            editToolbarItems
          }
        }
        .overlay(alignment: .top) {
          Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 48, height: 5)
            .padding(.top, 12)
            .accessibilityHidden(true)
        }
        // The player is covered here, so play/pause comes along.
        .overlay(alignment: .bottomTrailing) {
          NowPlayingPlayPauseButton()
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        },
        hosts: showingMixerSheet)
    }

    private var accent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    /// Hidden volume view to globally suppress the system volume HUD when
    /// physical hardware buttons are pressed.
    @ViewBuilder
    private var volumeHUDSuppressor: some View {
      #if os(iOS)
        SystemVolumeSlider()
          .frame(width: 0, height: 0)
          .opacity(0.001)
          .allowsHitTesting(false)
      #endif
    }

    @ViewBuilder
    private var mixerPage: some View {
      ZStack {
        // Background layer
        presetBackgroundView

        volumeHUDSuppressor

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
        editToolbarItems
      }
    }

    // MARK: - Main Content

    /// Blank while the header, the solo player or Quick Mix's column names what's playing.
    private var regularTitle: String {
      let named =
        showsRegularHeader || soloLayoutSound != nil
        || (audioManager.isQuickMix && quickMixShowsColumn)
      return named ? "" : navigationTitle
    }

    /// No preset header over the solo player, including an Edit Sound preview.
    private var showsRegularHeader: Bool {
      showsPresetPageHeader && soloLayoutSound == nil
    }

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
          // Regular width gives Quick Mix its own control column (no bar).
          QuickMixView(
            onOpenNowPlaying: isLargeDevice ? { showingNowPlaying = true } : nil,
            nowPlayingZoom: nowPlayingNamespace,
            onColumnChange: { quickMixShowsColumn = $0 })
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
      // The solo sound IS the now-playing surface: render the full Now Playing
      // player inline (square artwork, name, caption, transport, volume,
      // actions) instead of a separate sheet. If next/previous navigates onto a
      // preset (leaving solo), open the full Now Playing sheet for it rather than
      // dropping back to the grid.
      NowPlayingSheet(inline: true, onNavigateToPreset: { swapNowPlaying(showSheet: true) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Source the sheet's zoom transition from the inline solo player (the
        // mini-player, the usual source, is hidden during solo). Presenting or
        // dismissing the preset sheet then morphs to/from this player instead of
        // sliding. The two are never on screen together, so the id is unambiguous.
        .matchedTransitionSource(id: "nowPlaying", in: nowPlayingNamespace)
        .transition(.opacity)
    }

    /// The mixer beside wide Now Playing: Quick Mix's tiles or the preset's
    /// sounds, with the same reorder handling as the page.
    @ViewBuilder
    var nowPlayingSoundsPanel: some View {
      if audioManager.isQuickMix {
        QuickMixView()
      } else {
        soundsView
      }
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
        // Full-width rows would put sliders on a bent crease.
        listView
          .keepsToLeadingPageWhenFolded()
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

#if os(iOS) || os(visionOS)
  /// Editors dock beside a live preview on wide screens (leading, over the
  /// sidebar, so the page they change stays visible). Compact is unchanged.
  private struct EditorPlacement: ViewModifier {
    let layout: MixerLayout

    // One modifier chain whose values change, so folding or resizing while an
    // editor is open never rebuilds it (unsaved edits and previews survive).
    func body(content: Content) -> some View {
      #if os(iOS)
        if #available(iOS 27, *) {
          content.presentationPlacement(layout == .regular ? .leading : .automatic)
        } else {
          content
        }
      #else
        content
      #endif
    }
  }
#endif

#if os(iOS) || os(visionOS)
  /// Presents Now Playing to fill the screen on iPad via `fullScreenCover` (a
  /// sheet, even page-sized, stays an inset floating card there) and as a
  /// page-sized sheet on iPhone (for the system's grab-anywhere
  /// pull-to-dismiss). The player draws its own drag handle and chevron-down
  /// dismiss, so both paths hide the system indicator and rely on `onDismiss`.
  private struct NowPlayingPresentation<SheetBody: View>: ViewModifier {
    @Binding var isPresented: Bool
    let coversFullScreen: Bool
    let namespace: Namespace.ID
    @ViewBuilder var sheetBody: () -> SheetBody

    func body(content: Content) -> some View {
      if coversFullScreen {
        content.fullScreenCover(isPresented: $isPresented) {
          sheetBody()
            .navigationTransition(.zoom(sourceID: "nowPlaying", in: namespace))
        }
      } else {
        content.sheet(isPresented: $isPresented) {
          sheetBody()
            .presentationSizing(.page)
            .presentationDragIndicator(.hidden)
            .navigationTransition(.zoom(sourceID: "nowPlaying", in: namespace))
        }
      }
    }
  }
#endif

/// Reports whether the system keeps a vertical toolbar rail beside the view
/// (iPhone Duo's cover).
private struct ToolbarRailReader: ViewModifier {
  @Binding var isActive: Bool

  func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 27.1, *) {
        content.modifier(EdgeReader(isActive: $isActive))
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if os(iOS)
  @available(iOS 27.1, *)
  private struct EdgeReader: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
      content.onChange(of: edge != nil, initial: true) { _, active in
        isActive = active
      }
    }
  }
#endif
