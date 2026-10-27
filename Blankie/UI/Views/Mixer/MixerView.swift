//
//  MixerView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI
import os

private struct AnimationTrigger: Equatable {
  let soloMode: UUID?
  let quickMix: Bool
  let listView: Bool
  let isLoading: Bool
}

/// The iPhone stack's pushed pages. The Library is the root; the mixer is the
/// only pushed destination.
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
    /// iPhone Duo's cover has a vertical toolbar rail; AirPlay and Timer move onto it.
    @State private var hasToolbarRail = false
    @State private var showingVolumeZeroWarning = false
    @State private var isLandscape = false
    // Insets the Library lists, which the stack's safeAreaBar doesn't reach.
    @State private var nowPlayingBarHeight: CGFloat = 0
    /// The fold in window space (decides the propped-up layout) and in the
    /// playback bar's space (keeps the bar off a bent crease).
    @State private var windowFold = FoldInfo.none
    @State private var barFold = FoldInfo.none
    @State private var barWidth: CGFloat = 0
    /// Nightstand: the lower half can show the Library in place of the sounds,
    /// and an open Now Playing closes while propped up and reopens after.
    @State private var proppedShowsLibrary = false
    @State private var quickMixShowsColumn = false
    @State private var detailFold = FoldInfo.none
    @State private var detailWidth: CGFloat = 0
    @State private var nowPlayingBeforeProppedUp = false
    @State private var proppedLowerHeight: CGFloat = 0
    @State private var proppedBottomInset: CGFloat = 0
    @Namespace private var nowPlayingNamespace

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
      // Swapping cover and sheet rebuilds everything above, so the layout
      // handlers stay below this modifier.
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
      // The iPhone's player is a page and its mixer a sheet; wide layouts flip
      // that. Opening or closing iPhone Duo hands Now Playing over between them.
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
          // Closed from seated: the iPhone restores Now Playing as its page.
          if currentLayout == .compact && opensNowPlaying {
            iPhonePath = [.mixer]
          } else if currentLayout != .pages {
            showingNowPlaying = true
          }
        }
      }
      // Facing pages already show Now Playing on the left page.
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
      // Launch warning when Mix With Other Audio is on and Blankie's volume
      // with media is zero.
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
      // A failed launch restore opens on the Library. Initial, since a CarPlay
      // or widget launch can finish loading before this view exists.
      .onChange(of: presetManager.isLoading, initial: true) { _, loading in
        guard !loading, presetManager.lastPresetRestoreFailed else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { iPhonePath = [] }
      }
      // Onboarding created a preset: close Settings and show the mixer.
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
          .presentationSizing(.page)
      }
      // Quick Mix always lands on its mixer, including when started from a
      // widget, CarPlay or Siri.
      .onChange(of: audioManager.isQuickMix) { _, isQuickMix in
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

    /// Editors and the audio error alert. Attached to both the root and the
    /// iPhone's mixer sheet; only the front one hosts, since a view already
    /// showing a sheet can't present another.
    private func editorPresentations(_ content: some View, hosts: Bool) -> some View {
      content
        .modifier(AudioErrorHandler(hosts: hosts))
        .sheet(item: gated($soundToEdit, hosts)) { sound in
          SoundSheet(mode: .edit(sound))
            .modifier(EditorPlacement(layout: currentLayout))
            .interactiveDismissDisabled()
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

              // Animated artwork previews can disconnect the remote command
              // handlers, so restore them whatever the play state.
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

    /// Read live so a change in Settings applies immediately.
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
            // On iPhone Duo the mixer starts past the fold, flat or bent.
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
          .navigationTitle(
            regularTitle
          )
          .navigationBarTitleDisplayMode(.inline)
          // NavigationSplitView supplies the sidebar toggle.
          .toolbarBackground(.hidden, for: .navigationBar)
          .toolbar {
            editToolbarItems
          }
        }
        // Quick Mix carries its own controls.
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
      // The Library is the root, so it has no back button competing with the
      // Settings gear. Launch pushes the mixer on top.
      NavigationStack(path: $iPhonePath) {
        LibraryView(
          presentation: .page,
          onOpenSettings: { showingSettings = true },
          onSelection: { iPhonePath = [.mixer] },
          bottomBarHeight: nowPlayingBarHeight
        )
        .navigationDestination(for: IPhonePage.self) { _ in
          if opensNowPlaying {
            nowPlayingPage(drawsBackdrop: true, showsMixerButton: true)
          } else {
            mixerPage
          }
        }
      }
      // On the stack so the bar persists across the Library and the mixer.
      .nowPlayingBottomBar {
        if !hidesNowPlayingBarForSolo {
          nowPlayingBar
        }
      }
    }

    /// On the iPhone Library, a bar tap pushes the mixer. Everywhere else it
    /// expands Now Playing.
    private var barShowsMixer: Bool {
      !isLargeDevice && iPhonePath.isEmpty
    }

    /// Hides the mini player where the full player is already on screen (the
    /// solo player, the iPhone Now Playing page). The iPhone Library keeps it.
    private var hidesNowPlayingBarForSolo: Bool {
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

    /// Next/previous between a solo sound (inline player) and a preset (sheet).
    /// The layouts line up, so the swap skips animation.
    private func swapNowPlaying(showSheet: Bool) {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        if !showSheet { iPhonePath = [.mixer] }
        showingNowPlaying = showSheet
      }
    }

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

    /// Two pages split at the fold: Library and Now Playing, or Now Playing and
    /// the mixer. A solo sound's Now Playing spreads across both.
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

    /// The upright half shows what's playing; the flat half holds the sounds
    /// and controls.
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
              // Held flat, tiles fade out across the fold as they scroll up.
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
      // Side inset matches the bottom inset so the bar sits evenly in the corners.
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
        // The timer opens as a popover so it stays on the flat half.
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

    /// With a fold, flat or bent, the bar keeps to one page: past the fold
    /// beside the Library, otherwise the leading page.
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
            // Mixer-first presets on iPhone open Now Playing over the mixer.
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
        // Beside the open Duo's mixer page, these live in that page's bar.
        if spreads {
          playerToolbarItems(showsTimer: true)
        }
        // On the Duo's cover the favorite, AirPlay and Timer move to the rail.
        if showsMixerButton, hasToolbarRail, !spreads {
          playerToolbarItems(showsTimer: true, showsFavorite: true)
        }
        if showsMixerButton || spreads {
          editToolbarItems
        }
      }
    }

    /// Prefers the vertical rail on iPhone Duo; AirPlay's custom view would
    /// otherwise pull the group into a horizontal bar.
    @ToolbarContentBuilder
    private func playerToolbarItems(showsTimer: Bool, showsFavorite: Bool = false)
      -> some ToolbarContent
    {
      verticalPreferred(
        ToolbarItemGroup(placement: .topBarTrailing) {
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
            // The rail drops this custom view on rotation; a new identity restores it.
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

    /// Hidden volume view that suppresses the system volume HUD.
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
        presetBackgroundView

        volumeHUDSuppressor

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
          // currentPreset is nil until the restore completes.
          Color.clear
        } else if let soloSound = soloLayoutSound {
          soloModeView(for: soloSound)
        } else if audioManager.isQuickMix {
          // Regular width gives Quick Mix its own control column (no bar).
          QuickMixView(
            onOpenNowPlaying: isLargeDevice ? { showingNowPlaying = true } : nil,
            nowPlayingZoom: nowPlayingNamespace,
            onColumnChange: { quickMixShowsColumn = $0 })
        } else {
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
      // Solo renders the full player inline. Next/previous onto a preset opens
      // the Now Playing sheet.
      NowPlayingSheet(inline: true, onNavigateToPreset: { swapNowPlaying(showSheet: true) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The mini player is hidden during solo, so the zoom starts here. The
        // two are never on screen together, so the id stays unique.
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

    /// Per-preset view mode override, else the app-wide default.
    var effectiveUseListView: Bool {
      if let override = presetManager.currentPreset?.viewMode {
        return override == .list
      }
      return showingListView
    }

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

    // One modifier chain whose values change, so folding or resizing keeps the
    // open editor's unsaved edits.
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
  /// `fullScreenCover` on iPad (a page-sized sheet stays an inset card there);
  /// a page sheet on iPhone for pull-to-dismiss. The player draws its own handle.
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
