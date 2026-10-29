//
//  NowPlayingSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 11/24/25.
//
//  Apple Music-inspired Now Playing view with animated background
//

import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI

#if os(iOS) || os(visionOS)

  struct NowPlayingSheet: View {
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var audioManager = AudioManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var timerManager = TimerManager.shared

    @State private var globalSettings = GlobalSettings.shared
    /// Presented from inside the cover, since a sheet on the base hierarchy
    /// can't present over a fullScreenCover.
    @State private var showingTimer = false
    @State private var showingAddSound = false
    @State private var showingSaveMix = false
    var backgroundImage: PlatformImage?

    /// Inline in the mixer: no drag handle, sheet background or close chevron.
    var inline: Bool = false

    /// Fired when the inline player's next/previous lands on a preset, so the
    /// mixer can open the Now Playing sheet for it.
    var onNavigateToPreset: (() -> Void)?

    /// Fired when the sheet's next/previous lands on a single sound. The sheet
    /// dismisses and the inline player takes over.
    var onNavigateToSingle: (() -> Void)?

    /// The mixer shown beside the player on wide screens. Supplied by the mixer
    /// so reordering saves as usual.
    var soundsPanel: AnyView?

    /// The nightstand's upright half: artwork, title and progress to read from
    /// across the room, nothing to tap.
    var displayOnly = false

    /// The iPhone page keeps Timer in its nav bar and AirPlay on the mixer bar,
    /// so it drops the bottom row of action circles.
    var showsActions = true

    /// iPhone Duo open with a single sound: artwork on the left page, controls on the right.
    var spreadsAcrossFold = false

    /// iPhone's Now Playing page: a labeled Sound Mixer button under the volume.
    var onOpenMixer: (() -> Void)?
    /// The open Duo's right page has no side bar, so AirPlay joins that row.
    var actionRowIncludesAirPlay = false
    /// The Duo cover's side bar carries Timer instead.
    var actionRowIncludesTimer = true
    /// The Duo cover's side bar carries the favorite star, which leaves the title row.
    var favoriteInToolbar = false

    /// Which panel sits beside the player on wide screens. It survives folding,
    /// rotating and re-presenting.
    @SceneStorage("nowPlayingPanel") private var panelRaw = NowPlayingPanel.none.rawValue
    @State private var fold = FoldInfo.none

    /// CarPlay owns the volume, so the volume row hides while connected.
    private var isCarPlayConnected: Bool {
      audioManager.isCarPlayConnected
    }

    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var navigationEdge: Edge = .trailing
    @State private var artworkExpanded = false

    private var artworkTaskID: String {
      let single = audioManager.singleSound?.id.uuidString ?? ""
      let preset = presetManager.currentPreset?.id.uuidString ?? ""
      let mix = audioManager.unsavedMix?.originSoundFileName ?? ""
      return "\(single)-\(preset)-\(mix)"
    }

    var body: some View {
      Group {
        if inline {
          // Ignores the bottom safe area like the sheet, so the shared layout
          // clears the home indicator once and the rows line up. The outer
          // reader respects the safe area to report the insets.
          GeometryReader { safe in
            GeometryReader { proxy in
              nowPlayingView(in: proxy.size, bottomInset: safe.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .bottom)
          }
        } else {
          // Sized to the sheet, which is shorter than the window at the large
          // detent. The outer reader respects the safe area to report the insets.
          GeometryReader { safe in
            GeometryReader { proxy in
              ZStack {
                // Rounded top corners show during the zoom transition.
                Color.black
                  .overlay {
                    if audioManager.singleSound == nil && !audioManager.isQuickMix,
                      let image = backgroundImage
                    {
                      Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .blur(radius: 40)
                        .opacity(0.4)
                    } else {
                      LinearGradient(
                        colors: [
                          accentColor.opacity(0.6),
                          accentColor.opacity(0.3),
                          Color.black.opacity(0.8),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      )
                    }
                  }
                  .clipShape(
                    UnevenRoundedRectangle(
                      topLeadingRadius: 38,
                      bottomLeadingRadius: 0,
                      bottomTrailingRadius: 0,
                      topTrailingRadius: 38,
                      style: .continuous
                    )
                  )
                  .ignoresSafeArea()
                  .accessibilityHidden(true)

                // Respects the top inset (Dynamic Island) and side insets
                // (iPhone Duo's outer screen has a trailing status bar).
                let insets = safe.safeAreaInsets
                expandedPlayerView(
                  CGSize(
                    width: proxy.size.width - insets.leading - insets.trailing,
                    height: proxy.size.height),
                  bottomInset: insets.bottom
                )
                .padding(.top, insets.top > 0 ? insets.top : 10)
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
              }
              .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
          }
        }
      }
      .sheet(isPresented: $showingTimer) {
        // Detents override presentationSizing, so iPad gets `.form` without
        // detents and iPhone keeps its medium and large detents.
        if isRegularCanvas {
          TimerSheetView()
            .presentationSizing(.form)
        } else {
          TimerSheetView()
            .presentationDetents([.medium, .large])
        }
      }
      .sheet(isPresented: $showingAddSound) {
        MixSoundsPicker()
      }
      .saveMixSheet(isPresented: $showingSaveMix)
      // Inline, the root view's prompt covers it.
      .unsavedMixPrompt(isActive: !inline)
    }

    // MARK: - Now Playing View

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Regular in both directions (iPad, an open iPhone Duo): the centered,
    /// width-capped column.
    private var isRegularCanvas: Bool {
      horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    @ViewBuilder
    private func nowPlayingView(in size: CGSize, bottomInset: CGFloat) -> some View {
      if displayOnly {
        displayOnlyNowPlaying(in: size)
      } else {
        layoutNowPlaying(in: size, bottomInset: bottomInset)
      }
    }

    @ViewBuilder
    private func layoutNowPlaying(in size: CGSize, bottomInset: CGFloat) -> some View {
      let aspect = size.height > 0 ? size.width / size.height : 1
      if spreadsAcrossFold {
        spreadNowPlaying(in: size, bottomInset: bottomInset)
      } else if isRegularCanvas {
        regularNowPlaying(in: size, bottomInset: bottomInset)
      } else if dynamicTypeSize.isAccessibilitySize, aspect > 1 {
        accessibilityLandscape(in: size, bottomInset: bottomInset)
      } else if aspect > 1.6 || (verticalSizeClass == .compact && aspect > 1) {
        // Side by side on iPhone landscape, or when short and wide (iPhone Duo's
        // outer screen turned sideways), where the stacked column won't fit.
        landscapeNowPlaying(in: size, bottomInset: bottomInset)
      } else {
        portraitNowPlaying(in: size, bottomInset: bottomInset)
      }
    }

    private func displayOnlyNowPlaying(in size: CGSize) -> some View {
      let artworkSize = max(min(size.height - 64, size.width * 0.4), 100)
      return HStack(spacing: 24) {
        artworkView(size: artworkSize)
        VStack(alignment: .leading, spacing: 16) {
          infoRow()
          playbackProgressBar()
        }
        .frame(maxWidth: 380)
      }
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(false)
    }

    // MARK: - Portrait Layout

    @ViewBuilder
    private func portraitNowPlaying(in size: CGSize, bottomInset: CGFloat) -> some View {
      // Capped by height too, leaving room for the progress and volume rows in
      // a near-square pane (iPad landscape with the sidebar open).
      let artworkSize = max(min(size.width - 64, size.height - 240), 120)

      if dynamicTypeSize.isAccessibilitySize {
        accessibilityPortrait(artworkSize: artworkSize, bottomInset: bottomInset)
      } else {
        // Short screens (iPhone Duo's cover) shrink the artwork a step at a
        // time so the title and subtitle keep their room.
        ViewThatFits(in: .vertical) {
          ForEach([1, 0.9, 0.8, 0.7] as [CGFloat], id: \.self) { scale in
            portraitStack(artworkSize: max(artworkSize * scale, 120), bottomInset: bottomInset)
          }
        }
      }
    }

    /// Accessibility text sizes: the artwork folds into a thumbnail so the name
    /// reads in full. Only the text scrolls, and only when it has to.
    private func accessibilityPortrait(artworkSize: CGFloat, bottomInset: CGFloat) -> some View {
      VStack(spacing: 16) {
        accessibilityText(artworkSize: artworkSize)
        accessibilityControls
      }
      .padding(.bottom, max(20, bottomInset))
    }

    /// Accessibility sizes in landscape: text on one side, controls on the other.
    private func accessibilityLandscape(in size: CGSize, bottomInset: CGFloat) -> some View {
      let controlsWidth = min(size.width * 0.45, 400)
      let textWidth = size.width - controlsWidth - 16
      let artworkSize = max(min(textWidth - 64, size.height - bottomInset - 32), 120)
      return HStack(spacing: 16) {
        accessibilityText(artworkSize: artworkSize)
          .frame(width: textWidth)
        ViewThatFits(in: .vertical) {
          accessibilityControls
          ScrollView {
            accessibilityControls
          }
          .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: controlsWidth)
        .frame(maxHeight: .infinity)
      }
      .padding(.bottom, max(20, bottomInset))
    }

    /// Full size, then up to two sizes smaller, then scrolling.
    private func accessibilityText(artworkSize: CGFloat) -> some View {
      ViewThatFits(in: .vertical) {
        ForEach(textSizesToTry, id: \.self) { size in
          accessibilityInfo(artworkSize: artworkSize)
            .dynamicTypeSize(size)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        ScrollView {
          accessibilityInfo(artworkSize: artworkSize)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
    }

    private var accessibilityControls: some View {
      VStack(spacing: 16) {
        playbackProgressBar()
          .fixedSize(horizontal: false, vertical: true)
        transportControls()
        if !isCarPlayConnected {
          volumeSlider()
        }
        Group {
          if showsActions {
            bottomActionsRow
          }
          playerActionRow()
        }
        // Fixed-size glass: past this the labels outgrow their capsules.
        // Long-press shows them large instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
      }
    }

    /// The current text size, then up to two steps smaller, staying within the
    /// accessibility sizes.
    private var textSizesToTry: [DynamicTypeSize] {
      DynamicTypeSize.allCases
        .filter { $0.isAccessibilitySize && $0 <= dynamicTypeSize }
        .reversed()
        .prefix(3)
        .map { $0 }
    }

    private func accessibilityInfo(artworkSize: CGFloat) -> some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 8) {
          // The star keeps its place beside the artwork, expanded or not.
          artworkToggle(fullSize: artworkSize - 60)
          Spacer(minLength: 0)
          favoriteButton
        }
        infoTitle
          .fixedSize(horizontal: false, vertical: true)
        infoSubtitle?
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.top, 16)
    }

    /// A thumbnail that expands to the full artwork, and back.
    private func artworkToggle(fullSize: CGFloat) -> some View {
      Button {
        withAnimation(.smooth) { artworkExpanded.toggle() }
      } label: {
        changesWithItem(
          artworkContent(
            size: artworkExpanded ? fullSize : 72,
            cornerRadius: artworkExpanded ? 12 : 8))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(artworkExpanded ? Text("Hide Artwork") : Text("Show Artwork"))
    }

    private func portraitStack(artworkSize: CGFloat, bottomInset: CGFloat) -> some View {
      VStack(spacing: 0) {
        Spacer()
          .frame(minHeight: 16, maxHeight: 32)

        artworkView(size: artworkSize)
          .padding(.horizontal, 32)

        Spacer()

        infoRow()
          .fixedSize(horizontal: false, vertical: true)

        Spacer()
          .frame(maxHeight: 24)
        if showsProgressRow {
          playbackProgressBar()

          Spacer()
            .frame(maxHeight: 32)
        }

        transportControls()

        Spacer()
          .frame(maxHeight: 32)

        if !isCarPlayConnected {
          volumeSlider()

          Spacer()
            .frame(maxHeight: 32)
        }

        if showsActions {
          bottomActionsRow
        }

        playerActionRow()

        Spacer()
          .frame(height: max(20, bottomInset))
      }
      .modifier(SettlesRows(item: itemKey, showsProgress: showsProgressRow))
    }

    /// Sound Mixer (+ for a single sound), then AirPlay (open Duo only), then Timer.
    /// `fills` stretches the Sound Mixer button to the row's width.
    @ViewBuilder
    private func playerActionRow(fills: Bool = false) -> some View {
      if let onOpenMixer {
        HStack(spacing: 12) {
          if audioManager.singleSound == nil {
            Button(action: onOpenMixer) {
              // Falls back to "Mixer" so the label never truncates.
              ViewThatFits(in: .horizontal) {
                Label("Sound Mixer", systemImage: "slider.horizontal.3")
                Label("Mixer", systemImage: "slider.horizontal.3")
              }
              .lineLimit(1)
              .font(.body.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 22)
              .frame(maxWidth: fills ? .infinity : nil)
              .frame(height: 48)
              .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Sound Mixer"))
            .glassEffect(.regular.interactive(), in: .capsule)
            // An empty preset gets its sounds from the editor.
            .disabled(presetManager.currentPresetHasNoSounds)
            .opacity(presetManager.currentPresetHasNoSounds ? 0.4 : 1)
            .overlay(alignment: .topTrailing) {
              // An empty preset's editor carries the badge.
              if silentPresetMessage != nil, !presetManager.currentPresetHasNoSounds {
                Image(systemName: "exclamationmark")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(.white)
                  .frame(width: 22, height: 22)
                  .background(accentColor, in: .circle)
                  .offset(x: 4, y: -4)
                  .accessibilityHidden(true)
              }
            }
            .accessibilityValue(silentPresetMessage.map { Text($0) } ?? Text(verbatim: ""))
          } else {
            addSoundButton(size: 48)
          }

          #if os(iOS)
            if actionRowIncludesAirPlay {
              AirPlayRouteButton(activeColor: accentColor, inactiveColor: .white)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("AirPlay"))
            }
          #endif

          if actionRowIncludesTimer {
            Button {
              showingTimer = true
            } label: {
              Image(systemName: "timer")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(timerManager.isTimerActive ? accentColor : .white)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(Text("Timer"))
          }
        }
      }
    }

    // MARK: - iPad Layout

    /// One centered column, or the column beside a Sounds or Timer panel. With
    /// a fold, flat or bent, the column keeps to the leading page.
    @ViewBuilder
    private func regularNowPlaying(in size: CGSize, bottomInset: CGFloat) -> some View {
      let panel = visiblePanel
      let creaseSplit = CreaseInsets.leadingPage(containerWidth: size.width, fold: fold) != nil
      let split = CreaseInsets.split(containerWidth: size.width, fold: fold)
      let columnWidth = panel != .none || creaseSplit ? split.leading : size.width

      HStack(spacing: 0) {
        regularColumn(width: columnWidth, height: size.height, bottomInset: bottomInset)
          .frame(width: columnWidth)
        // Nothing on the crease band itself.
        Color.clear
          .frame(width: split.gap)
        switch panel {
        case .sounds:
          soundsPanel
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .timer:
          TimerPanelView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .none:
          if creaseSplit { Spacer(minLength: 0) }
        }
      }
      .onFoldChange { fold = $0 }
    }

    private func regularColumn(width: CGFloat, height: CGFloat, bottomInset: CGFloat)
      -> some View
    {
      let artworkSize = max(min(width - 96, height * 0.42), 140)
      return VStack(spacing: 0) {
        Spacer(minLength: 16)
        artworkView(size: artworkSize)
        Spacer().frame(height: 28)
        infoRow()
        Spacer().frame(height: 20)
        playbackProgressBar()
        Spacer().frame(height: 24)
        transportControls()
        Spacer().frame(height: 24)
        if !isCarPlayConnected {
          volumeSlider()
        }
        Spacer(minLength: 16)
        regularBottomRow
        Spacer()
          .frame(height: max(20, bottomInset))
      }
      .frame(maxWidth: 560)
    }

    /// Close and AirPlay sit leading. The panel toggles sit trailing (filled when open).
    private var regularBottomRow: some View {
      GlassEffectContainer(spacing: 16) {
        HStack(spacing: 16) {
          if !inline {
            Button {
              onDismiss?()
            } label: {
              Image(systemName: "chevron.down")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 20, weight: .medium))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .modifier(NowPlayingActionGlass())
          }
          #if os(iOS)
            AirPlayRouteButton(activeColor: accentColor, inactiveColor: .white.opacity(0.35))
              .frame(width: 44, height: 44)
              .accessibilityLabel(Text("AirPlay"))
              .frame(width: 56, height: 56)
              .modifier(NowPlayingActionGlass())
          #endif
          Spacer(minLength: 0)
          panelToggle(.timer, symbol: "timer", label: Text("Timer"))
          if audioManager.singleSound != nil {
            addSoundButton(size: 56)
          } else {
            panelToggle(.sounds, symbol: "slider.horizontal.3", label: Text("Sounds"))
              .disabled(soundsPanel == nil)
          }
        }
        .padding(.horizontal, 32)
      }
    }

    /// Starts a mix from the single sound.
    private func addSoundButton(size: CGFloat) -> some View {
      Button {
        showingAddSound = true
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(.white)
          .frame(width: size, height: size)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Add Sound"))
      .glassEffect(.regular.interactive(), in: .circle)
    }

    private func panelToggle(_ target: NowPlayingPanel, symbol: String, label: Text)
      -> some View
    {
      let isOpen = visiblePanel == target
      return Button {
        panelRaw = (isOpen ? NowPlayingPanel.none : target).rawValue
      } label: {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(
            isOpen
              ? .black
              : (target == .timer && timerManager.isTimerActive ? accentColor : .white.opacity(0.7))
          )
          .frame(width: 56, height: 56)
          .background(Circle().fill(.white.opacity(isOpen ? 1 : 0)))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .accessibilityAddTraits(isOpen ? [.isSelected] : [])
      .modifier(NowPlayingActionGlass())
    }

    /// The stored panel, minus one that can't show (no mixer for a single sound).
    private var visiblePanel: NowPlayingPanel {
      let panel = NowPlayingPanel(rawValue: panelRaw) ?? .none
      if panel == .sounds, audioManager.singleSound != nil || soundsPanel == nil {
        return .none
      }
      return panel
    }

    // MARK: - Landscape Layout

    /// Artwork fills the page before the fold, fading toward it. The controls
    /// sit centered on the page after it.
    private func spreadNowPlaying(in size: CGSize, bottomInset: CGFloat) -> some View {
      let split = CreaseInsets.split(containerWidth: size.width, fold: fold)
      return HStack(spacing: 0) {
        // An oversized, clipped overlay on a page-sized frame fills the page
        // (safe areas included) without growing the layout.
        Color.clear
          .frame(width: split.leading)
          .frame(maxHeight: .infinity)
          .overlay {
            changesWithItem(
              artworkContent(size: max(split.leading, size.height) + 120, cornerRadius: 0))
          }
          .clipped()
          .mask {
            LinearGradient(
              stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
              startPoint: .leading, endPoint: .trailing)
          }
          .ignoresSafeArea(edges: .vertical)
          .accessibilityHidden(true)
        Color.clear
          .frame(width: split.gap)
        VStack(spacing: 0) {
          Spacer()
          infoRow()
          Spacer()
            .frame(maxHeight: 24)
          playbackProgressBar()
          Spacer()
            .frame(maxHeight: 32)
          transportControls()
          Spacer()
            .frame(maxHeight: 32)
          if !isCarPlayConnected {
            volumeSlider()
          }
          if showsActions {
            Spacer()
              .frame(maxHeight: 32)
            bottomActionsRow
          }
          Spacer()
        }
        .padding(.trailing, 16)
      }
      .onFoldChange { fold = $0 }
    }

    /// Landscape: the artwork as large as fits, beside a controls column of
    /// its height, centered together. Wider screens get a wider column.
    private func landscapeNowPlaying(in size: CGSize, bottomInset: CGFloat) -> some View {
      // Centers in the full height. The top bar's buttons sit at the far edges.
      GeometryReader { proxy in
        landscapeLayout(in: proxy.size, bottomInset: bottomInset)
      }
      .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    /// iPhone 17 Pro proportions (artwork 290, gap 48, column 300, margins 56),
    /// scaled. The artwork shrinks before the column narrows past its rows.
    private func landscapeLayout(in size: CGSize, bottomInset: CGFloat) -> some View {
      let gapRatio: CGFloat = 48 / 290
      let columnRatio: CGFloat = 300 / 290
      let marginRatio: CGFloat = 56 / 290
      // The transport needs 180. The Sound Mixer row ("Mixer" plus a 60pt
      // slot per circle) or the sheet's row of circles may need more.
      let circles = (actionRowIncludesAirPlay ? 1 : 0) + (actionRowIncludesTimer ? 1 : 0)
      let mixerRow = onOpenMixer != nil ? 136 + CGFloat(circles) * 60 : 0
      let minColumn = max(180, mixerRow, showsActions ? 208 : 0)
      let minMargin: CGFloat = 16
      let fixedRatios = 1 + gapRatio + marginRatio * 2
      let proportional = min(
        size.width / (fixedRatios + columnRatio), (size.width - minColumn) / fixedRatios)
      // Centered on the full height, clearing the home indicator by the same
      // amount at both edges.
      let tallest = size.height - (bottomInset + 24) * 2
      let artworkSize = max(min(proportional, tallest), 120)
      let spacing = artworkSize * gapRatio
      let controlsWidth = min(
        max(artworkSize * columnRatio, minColumn),
        size.width - artworkSize - spacing - minMargin * 2)

      return HStack(spacing: spacing) {
        artworkView(size: artworkSize, shrinksWhenPaused: false)

        // Scrolls when large text or a wrapped title outgrows the artwork's height.
        ViewThatFits(in: .vertical) {
          landscapeControls
          ScrollView {
            landscapeControls
              .padding(.vertical, 8)
          }
          .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: controlsWidth, height: artworkSize)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Rows share the column's edges and line up with the artwork's top and bottom.
    private var landscapeControls: some View {
      VStack(spacing: 0) {
        infoRow(inset: 0, alignment: .top)
        Spacer(minLength: 8)
        if showsProgressRow {
          playbackProgressBar(inset: 0)
          Spacer(minLength: 8)
        }
        transportControls(spread: true)
        Spacer(minLength: 8)
        // With its buttons on the toolbar rail (iPhone Duo's cover), the
        // column ends at the volume, level with the artwork's bottom.
        let hasActionRow = showsActions || onOpenMixer != nil
        if !isCarPlayConnected {
          volumeSlider(inset: 0)
          if hasActionRow { Spacer(minLength: 8) }
        }
        if showsActions {
          bottomActionsRow
        }
        playerActionRow(fills: true)
      }
      .modifier(SettlesRows(item: itemKey, showsProgress: showsProgressRow))
    }

    // MARK: - Shared Components

    @ViewBuilder
    /// Paused, the artwork shrinks back, except beside a column it lines up with.
    private func artworkView(size: CGFloat, shrinksWhenPaused: Bool = true) -> some View {
      changesWithItem(artworkContent(size: size))
        .scaleEffect(audioManager.isGloballyPlaying || !shrinksWhenPaused ? 1.0 : 0.85)
        .shadow(
          color: .black.opacity(0.3),
          radius: audioManager.isGloballyPlaying ? 20 : 10,
          x: 0,
          y: audioManager.isGloballyPlaying ? 10 : 5
        )
        .animation(
          .spring(response: 0.4, dampingFraction: 0.6), value: audioManager.isGloballyPlaying
        )
        .accessibilityHidden(true)
    }

    /// The artwork itself: the preset's image, or the shared fallback card.
    @ViewBuilder
    private func artworkContent(size: CGFloat, cornerRadius: CGFloat = 12) -> some View {
      Group {
        if let singleSound = audioManager.singleSound {
          FallbackArtwork(
            glyph: .symbol(singleSound.systemIconName),
            accent: globalSettings.customAccentColor ?? .accentColor,
            size: size,
            cornerRadius: cornerRadius,
            glyphFraction: 0.4
          )
        } else if let image = backgroundImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
          FallbackArtwork(
            glyph: NowPlayingDisplay.mixFallbackGlyph(),
            accent: presetManager.currentPreset?.accentColor
              ?? globalSettings.customAccentColor ?? .accentColor,
            size: size,
            cornerRadius: cornerRadius,
            glyphFraction: 0.5
          )
        }
      }
    }

    private var currentProgressAnchor: (elapsed: TimeInterval, duration: TimeInterval)? {
      if timerManager.isTimerActive, timerManager.selectedDuration > 0 {
        let elapsed = timerManager.selectedDuration - timerManager.remainingTime
        return (max(0, elapsed), timerManager.selectedDuration)
      }

      let anchorSound =
        audioManager.singleSound
        ?? audioManager.sounds
        .filter { $0.isSelected }
        .max { $0.playbackDuration < $1.playbackDuration }

      guard let anchorSound, anchorSound.playbackDuration > 0 else { return nil }
      return (anchorSound.playbackPosition, anchorSound.playbackDuration)
    }

    /// A preset with nothing to play: empty (the editor badges itself), or
    /// every sound turned off. Play is disabled then, so this says why.
    private var silentPresetMessage: LocalizedStringKey? {
      guard presetManager.currentPreset != nil, audioManager.singleSound == nil,
        !audioManager.isQuickMix, !audioManager.isGloballyPlaying,
        !audioManager.hasSelectedSounds, !presetManager.isLoading
      else { return nil }
      return presetManager.currentPresetHasNoSounds
        ? "No sounds in this preset" : "No Sounds Playing"
    }

    /// When false, layouts drop the progress row and its spacing.
    private var showsProgressRow: Bool {
      silentPresetMessage != nil
        || globalSettings.showsPlaybackProgress(timerActive: timerManager.isTimerActive)
    }

    @ViewBuilder
    private func playbackProgressBar(inset: CGFloat = 32) -> some View {
      if let message = silentPresetMessage {
        Label(message, systemImage: "speaker.slash.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(accentColor)
      } else if globalSettings.showsPlaybackProgress(timerActive: timerManager.isTimerActive) {
        let anchor = currentProgressAnchor
        let duration = anchor?.duration ?? 0

        if audioManager.isGloballyPlaying && duration > 0 {
          TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            playbackBar(duration: duration, inset: inset)
          }
        } else {
          playbackBar(duration: duration, inset: inset)
        }
      }
    }

    @ViewBuilder
    private func playbackBar(duration: TimeInterval, inset: CGFloat) -> some View {
      let anchor = currentProgressAnchor
      let elapsed = anchor?.elapsed ?? 0

      VStack(spacing: 8) {
        // Bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.white.opacity(0.3))
              .frame(height: 6)

            if duration > 0 {
              Capsule()
                .fill(Color.white)
                .frame(
                  width: max(0, min(geo.size.width, geo.size.width * CGFloat(elapsed / duration))),
                  height: 6)
            }
          }
        }
        .frame(height: 6)
        .accessibilityHidden(true)

        HStack {
          if timerManager.isTimerActive {
            Text("Pausing at \(timerEndTimeString)")
            Spacer()
            Text(formatTime(-timerManager.remainingTime))
          } else {
            Text(duration > 0 ? formatTime(elapsed) : "--:--")
            Spacer()
            if duration > 0 {
              HStack(spacing: 3) {
                Text(formatTime(duration))
                Image(systemName: "repeat")
                  .accessibilityHidden(true)
              }
            } else {
              Text("--:--")
            }
          }
        }
        .font(.caption2.monospacedDigit())
        .foregroundColor(.white.opacity(0.6))
      }
      .padding(.horizontal, inset)
    }

    private var timerEndTimeString: String {
      (timerManager.getEndTime() ?? Date())
        .formatted(date: .omitted, time: .shortened)
    }

    // While mixing with other audio the hardware slider moves every app at
    // once, so a labeled slider for volumeWithOtherAudio replaces it.
    @ViewBuilder
    private func volumeSlider(inset: CGFloat = 32) -> some View {
      #if os(iOS) || os(visionOS)
        if globalSettings.mixWithOthers {
          blankieVolumeRow(inset: inset)
        } else {
          systemVolumeRow(inset: inset)
        }
      #else
        systemVolumeRow(inset: inset)
      #endif
    }

    private func systemVolumeRow(inset: CGFloat) -> some View {
      HStack(spacing: 15) {
        Image(systemName: "speaker.fill")
          .foregroundColor(.gray)
          .font(.caption)
          .accessibilityHidden(true)

        #if os(iOS)
          SystemVolumeSlider()
            .frame(height: 30)
            .accessibilityLabel(Text("Volume"))
        #else
          Slider(
            value: Binding(
              get: { globalSettings.volume },
              set: { globalSettings.setVolume($0) }
            ),
            in: 0...1,
            onEditingChanged: { editing in
              withAnimation(.easeOut(duration: 0.2)) {
                isEditingVolume = editing
              }
            }
          )
          .tint(.white.opacity(0.7))
          .sliderThumbVisibility(isEditingVolume ? .visible : .hidden)
          .accessibilityLabel(Text("Volume"))
          .accessibilityValue(
            Text(Double(globalSettings.volume).formatted(.percent.precision(.fractionLength(0)))))
        #endif

        Image(systemName: "speaker.wave.3.fill")
          .foregroundColor(.gray)
          .font(.caption)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, inset)
    }

    #if os(iOS) || os(visionOS)
      private func blankieVolumeRow(inset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
          Text("Blankie Volume with Media")
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.7))
            .accessibilityHidden(true)

          HStack(spacing: 15) {
            Image(systemName: "speaker.fill")
              .foregroundColor(.gray)
              .font(.caption)
              .accessibilityHidden(true)

            Slider(
              value: Binding(
                get: { globalSettings.volumeWithOtherAudio },
                set: { globalSettings.setVolumeWithOtherAudio($0) }
              ),
              in: 0...1
            )
            .tint(accentColor)
            .accessibilityLabel(Text("Blankie Volume with Media"))
            .accessibilityValue(
              Text(
                globalSettings.volumeWithOtherAudio.formatted(
                  .percent.precision(.fractionLength(0)))))

            Image(systemName: "speaker.wave.3.fill")
              .foregroundColor(.gray)
              .font(.caption)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, inset)
      }
    #endif

    // MARK: - Helper Properties

    /// nil for Quick Mix and an unsaved mix, which can't be favorites.
    private var favoriteToken: String? {
      if let single = audioManager.singleSound {
        return PlayableItem.single(fileName: single.fileName).token
      }
      guard !audioManager.isQuickMix, let preset = presetManager.currentPreset else { return nil }
      return preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
    }

    // MARK: - Actions Row

    /// Single sound uses the app accent, ignoring the last preset's accent.
    private var accentColor: Color {
      if audioManager.singleSound != nil {
        return globalSettings.customAccentColor ?? .accentColor
      }
      return presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
        ?? .accentColor
    }

    // MARK: - Info Row

    /// The nightstand's title gets a third line. Accessibility sizes have no
    /// limit, so the layout scrolls.
    private var titleLineLimit: Int? {
      dynamicTypeSize.isAccessibilitySize ? nil : (displayOnly ? 3 : 2)
    }

    private var subtitleLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }

    @ViewBuilder
    /// `alignment` top pins the title to the row's top edge, beside artwork.
    private func infoRow(inset: CGFloat = 32, alignment: VerticalAlignment = .center) -> some View {
      changesWithItem(infoRowContent(inset: inset, alignment: alignment))
    }

    private func infoRowContent(inset: CGFloat, alignment: VerticalAlignment) -> some View {
      HStack(alignment: alignment) {
        VStack(alignment: .leading, spacing: 2) {
          infoTitle
            .lineLimit(titleLineLimit)
            .minimumScaleFactor(displayOnly ? 0.6 : 1)
          infoSubtitle?
            .lineLimit(subtitleLineLimit)
        }
        .accessibilityElement(children: .combine)

        Spacer()

        if !displayOnly {
          favoriteButton
        }
      }
      .padding(.horizontal, inset)
    }

    private var infoTitle: some View {
      Group {
        if let singleSound = audioManager.singleSound {
          Text(singleSound.localizedTitle)
        } else if let unsavedMix = audioManager.unsavedMix {
          Text(verbatim: unsavedMix.name)
        } else if let preset = presetManager.currentPreset {
          Text(verbatim: preset.displayName)
        } else {
          Text(audioManager.isQuickMix ? "Quick Mix" : "Blankie")
        }
      }
      .font(.title2)
      .fontWeight(.bold)
      .foregroundColor(.white)
    }

    /// A built-in sound's caption, a custom sound's author, or a preset's creator. An unsaved
    /// mix has none.
    private var infoSubtitle: Text? {
      let text: Text?
      if let singleSound = audioManager.singleSound {
        if let subtitle = singleSound.localizedSubtitle {
          text = Text(subtitle)
        } else if singleSound.isCustom, let author = singleSound.creditedAuthor {
          text = Text(author)
        } else {
          text = nil
        }
      } else if audioManager.unsavedMix != nil {
        text = nil
      } else if let creatorName = presetManager.currentPreset?.creatorName,
        !creatorName.isEmpty
      {
        text = Text(creatorName)
      } else {
        text = nil
      }
      return text.map { $0.font(.title3).foregroundColor(.white.opacity(0.7)) }
    }

    @ViewBuilder
    private var favoriteButton: some View {
      if audioManager.unsavedMix != nil, !favoriteInToolbar {
        // An unsaved mix can't be a favorite, so Save takes the star's place.
        Button {
          showingSaveMix = true
        } label: {
          Text("Save")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(accentColor, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Save Mix"))
        #if os(iOS)
          .frame(minHeight: 44, alignment: .trailing)
        #endif
      } else if let token = favoriteToken, !favoriteInToolbar {
        let starred = globalSettings.isStarred(token)
        Button {
          globalSettings.toggleStarred(token)
          favoriteHapticTrigger += 1
        } label: {
          Image(systemName: starred ? "star.fill" : "star")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(starred ? accentColor : .white.opacity(0.7))
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.15))
            .clipShape(Circle())
        }
        .accessibilityLabel(starred ? Text("Unfavorite") : Text("Favorite"))
        #if os(iOS)
          // Trailing, so the star lines up with the row edges below it.
          .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        #endif
      }
    }

    /// Runs next/previous and any single sound/preset hand-off without animation, so the
    /// layout behind the player stays put. Artwork and title slide in from `edge`.
    private func performNavigation(from edge: Edge, _ navigate: () -> Void) {
      navigationEdge = edge
      navigate()
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        handlePostNavigation()
      }
    }

    private static let itemChangeAnimation = Animation.smooth(duration: 0.35)
    private static let itemFadeOut: TimeInterval = 0.12

    /// What's playing, so its artwork and title can transition when it changes.
    private var itemKey: String {
      if let single = audioManager.singleSound { return "sound:\(single.fileName)" }
      // The mix's name changes as sounds come and go, so it's keyed by its first sound.
      if let mix = audioManager.unsavedMix { return "unsavedMix:\(mix.originSoundFileName)" }
      if audioManager.isQuickMix { return "quickMix" }
      return "preset:\(presetManager.currentPreset?.id.uuidString ?? "none")"
    }

    /// Fades the outgoing item out, then slides the incoming one in from the
    /// side the person navigated toward, so the two titles never overlap.
    private func changesWithItem(_ content: some View) -> some View {
      let shift: CGFloat = navigationEdge == .trailing ? 60 : -60
      return ZStack {
        content
          .id(itemKey)
          .transition(
            .asymmetric(
              insertion: AnyTransition.offset(x: shift).combined(with: .opacity)
                .animation(.smooth(duration: 0.3).delay(Self.itemFadeOut)),
              removal: AnyTransition.offset(x: -shift / 3).combined(with: .opacity)
                .animation(.easeOut(duration: Self.itemFadeOut))))
      }
      .animation(Self.itemChangeAnimation, value: itemKey)
    }

    /// Single sounds play in the inline player and presets in the sheet, so
    /// crossing between them hands off.
    private func handlePostNavigation() {
      if inline {
        if audioManager.singleSound == nil { onNavigateToPreset?() }
      } else {
        if audioManager.singleSound != nil { onNavigateToSingle?() }
      }
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private func transportControls(spread: Bool = false) -> some View {
      let canNavigate = audioManager.canNavigateNextPrevious
      // Play would be silent with nothing selected, but pause is always available.
      let canPlayPause = audioManager.isGloballyPlaying || audioManager.hasSelectedSounds
      // Spread: previous and next sit on the column's edges.
      HStack(spacing: spread ? 0 : 48) {
        if !spread { Spacer() }

        if canNavigate {
          Button {
            audioManager.leaveUnsavedMixAsking {
              performNavigation(from: .leading, audioManager.navigateToPreviousPreset)
            }
          } label: {
            Image(systemName: "backward.fill")
              .font(.system(size: 32))
              .foregroundColor(.white.opacity(0.8))
          }
          .accessibilityLabel(Text("Previous"))
          #if os(iOS)
            .frame(minWidth: 44, minHeight: 44, alignment: spread ? .leading : .center)
          #endif
        } else {
          Color.clear.frame(width: 32, height: 32)
        }

        if spread { Spacer(minLength: 16) }

        Button {
          audioManager.togglePlayback()
        } label: {
          Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 48))
            .foregroundColor(.white.opacity(canPlayPause ? 1 : 0.4))
            .frame(width: 60, height: 60, alignment: .center)
        }
        .disabled(!canPlayPause)
        .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))

        if spread { Spacer(minLength: 16) }

        if canNavigate {
          Button {
            audioManager.leaveUnsavedMixAsking {
              performNavigation(from: .trailing, audioManager.navigateToNextPreset)
            }
          } label: {
            Image(systemName: "forward.fill")
              .font(.system(size: 32))
              .foregroundColor(.white.opacity(0.8))
          }
          .accessibilityLabel(Text("Next"))
          #if os(iOS)
            .frame(minWidth: 44, minHeight: 44, alignment: spread ? .trailing : .center)
          #endif
        } else {
          Color.clear.frame(width: 32, height: 32)
        }

        if !spread { Spacer() }
      }
    }

    // MARK: - Bottom Actions Row

    private var bottomActionsRow: some View {
      GlassEffectContainer(spacing: 20) {
        bottomActionsContent
      }
    }

    private var bottomActionsContent: some View {
      HStack(spacing: 20) {
        if !inline {
          Button {
            onDismiss?()
          } label: {
            Image(systemName: "chevron.down")
              .foregroundColor(.white.opacity(0.7))
              .font(.system(size: 20, weight: .medium))
              .frame(width: 56, height: 56)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Close"))
          .modifier(NowPlayingActionGlass())
        }

        #if os(iOS)
          AirPlayRouteButton(
            activeColor: accentColor,
            inactiveColor: .white.opacity(0.35)
          )
          .frame(width: 44, height: 44)
          .accessibilityLabel(Text("AirPlay"))
          .frame(width: 56, height: 56)
          .contentShape(Circle())
          .modifier(NowPlayingActionGlass())
        #endif

        Button {
          showingTimer = true
        } label: {
          Image(systemName: "timer")
            .foregroundColor(timerManager.isTimerActive ? accentColor : .white.opacity(0.7))
            .font(.system(size: 20, weight: .medium))
            .frame(width: 56, height: 56)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Timer"))
        .modifier(NowPlayingActionGlass())
      }
    }

    // MARK: - Expanded Player View

    @ViewBuilder
    private func expandedPlayerView(_ size: CGSize, bottomInset: CGFloat) -> some View {
      VStack(spacing: 0) {
        dragIndicator
          .padding(.top, 12)
          .padding(.bottom, 16)

        nowPlayingView(in: size, bottomInset: bottomInset)
      }
    }

    private var dragIndicator: some View {
      Capsule()
        .fill(Color.white.opacity(0.3))
        .frame(width: 48, height: 5)
        .accessibilityHidden(true)
    }

    // MARK: - Helper Methods

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      timeInterval.minuteSecondClock
    }

  }

  /// Rows slide into place when the item changes or the progress row comes or goes.
  private struct SettlesRows: ViewModifier {
    let item: String
    let showsProgress: Bool

    func body(content: Content) -> some View {
      content
        .animation(.smooth(duration: 0.35), value: item)
        .animation(.smooth(duration: 0.35), value: showsProgress)
    }
  }

  /// What sits beside Now Playing on wide screens.
  enum NowPlayingPanel: String {
    case none, sounds, timer
  }

  private struct NowPlayingActionGlass: ViewModifier {
    func body(content: Content) -> some View {
      content.glassEffect(.regular.interactive(), in: .circle)
    }
  }

  struct NowPlayingPreviewWrapper: View {
    init() {
      let mockPreset = Preset(
        id: UUID(),
        name: "Deep Sleep",
        soundStates: [],
        isDefault: false,
        createdVersion: nil,
        creatorName: "Blankie User"
      )
      PresetManager.shared.currentPreset = mockPreset
      AudioManager.shared.isGloballyPlaying = true
    }

    var body: some View {
      NowPlayingSheet()
    }
  }

  #Preview("Portrait") {
    NowPlayingPreviewWrapper()
  }

  #Preview("Landscape", traits: .landscapeLeft) {
    NowPlayingPreviewWrapper()
  }

  // MARK: - System Volume Slider

  final class CenteredVolumeView: MPVolumeView {
    override func layoutSubviews() {
      super.layoutSubviews()
      // MPVolumeView replaces its slider lazily (including after route
      // changes), so styling happens on every layout pass.
      if let slider = subviews.first(where: { $0 is UISlider }) as? UISlider {
        slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.7)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
      }
    }

    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
      let rect = super.volumeSliderRect(forBounds: bounds)
      return CGRect(
        x: rect.minX, y: bounds.midY - rect.height / 2,
        width: rect.width, height: rect.height)
    }
  }

  struct SystemVolumeSlider: View {
    var body: some View {
      #if targetEnvironment(simulator)
        // The simulator has no hardware volume slider, so a disabled bar holds the layout.
        Slider(value: .constant(0.5), in: 0...1)
          .tint(.white.opacity(0.7))
          .sliderThumbVisibility(.hidden)
          .disabled(true)
          .accessibilityHidden(true)
      #else
        NativeSystemVolumeSlider()
      #endif
    }
  }

  private struct NativeSystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
      let volumeView = CenteredVolumeView(frame: .zero)
      // Set on MPVolumeView, so it applies before the lazy UISlider exists.
      volumeView.setVolumeThumbImage(UIImage(), for: .normal)
      return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
      uiView.setNeedsLayout()
    }
  }

  // MARK: - AirPlay Route Picker

  #if os(iOS)
    /// System AirPlay / output-route button. Defaults match the white-on-glass
    /// Now Playing controls, but the mini bar passes adaptive label colors instead.
    struct AirPlayRoutePickerView: UIViewRepresentable {
      var tint: UIColor = UIColor.white.withAlphaComponent(0.7)
      var activeTint: UIColor = .white
      var forcesDarkAppearance = true

      func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = tint
        picker.activeTintColor = activeTint
        picker.prioritizesVideoDevices = false
        if forcesDarkAppearance {
          picker.overrideUserInterfaceStyle = .dark
        }
        return picker
      }

      // The route sheet renders outside the app's window, so no view override
      // reaches it. Only the Info.plist UIUserInterfaceStyle sets its appearance.
      func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }

    /// Maps the output route's `portType` to a generic symbol and whether audio
    /// left the built-in speaker. SF Symbols restricts device glyphs (AirPods,
    /// HomePod, Beats) to that exact product, and `portName` is user-editable.
    final class AudioRouteObserver: ObservableObject {
      @Published private(set) var symbolName = "airplayaudio"
      @Published private(set) var isExternal = false

      init() {
        update()
        NotificationCenter.default.addObserver(
          self, selector: #selector(routeChanged),
          name: AVAudioSession.routeChangeNotification, object: nil)
      }

      @objc private func routeChanged() {
        DispatchQueue.main.async { [weak self] in self?.update() }
      }

      private func update() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else {
          (symbolName, isExternal) = ("airplayaudio", false)
          return
        }
        switch port.portType {
        case .builtInSpeaker, .builtInReceiver:
          (symbolName, isExternal) = ("airplayaudio", false)
        case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
          (symbolName, isExternal) = ("headphones", true)
        case .carAudio:
          (symbolName, isExternal) = ("car", true)
        case .HDMI, .displayPort:
          (symbolName, isExternal) = ("tv", true)
        case .usbAudio, .lineOut, .thunderbolt:
          (symbolName, isExternal) = ("hifispeaker.fill", true)
        case .airPlay:
          // HomePod, Apple TV and other AirPlay receivers all report this type.
          (symbolName, isExternal) = ("airplayaudio", true)
        default:
          (symbolName, isExternal) = ("airplayaudio", true)
        }
      }
    }

    /// A themed route icon drawn over a transparent `AVRoutePickerView`, which
    /// still takes the tap and presents the system picker.
    struct AirPlayRouteButton: View {
      var activeColor: Color
      var inactiveColor: Color
      @StateObject private var route = AudioRouteObserver()

      var body: some View {
        AirPlayRoutePickerView(tint: .clear, activeTint: .clear)
          .overlay {
            Image(systemName: route.symbolName)
              .font(.system(size: 20, weight: .medium))
              .foregroundStyle(route.isExternal ? activeColor : inactiveColor)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
      }
    }
  #endif

#endif
