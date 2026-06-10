//
//  LibraryView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI
import TipKit
import UniformTypeIdentifiers
import os

/// Shared "now playing" treatment for Library rows. Sidebar rows highlight
/// the whole row and tint the title with the active accent; every presentation
/// shows an animated equalizer glyph in place of the old checkmark.
enum LibraryRowStyle {
  static func titleColor(
    isCurrent: Bool, accent: Color, presentation: LibraryView.Presentation
  ) -> Color {
    (presentation == .sidebar || presentation == .menuBar) && isCurrent ? accent : .primary
  }

  /// Row backdrop. Sidebar: an inset accent pill behind only the active row,
  /// like the system sidebar selection. Page: a uniform dark glass card —
  /// material blur, so the artwork backdrop glows through without making the
  /// row read as transparent. `nil` falls back to the list's default row
  /// background.
  static func rowBackground(
    isCurrent: Bool, accent: Color, presentation: LibraryView.Presentation
  ) -> RowBackground? {
    switch presentation {
    case .sidebar, .menuBar:
      return isCurrent ? RowBackground(style: .sidebarPill(accent)) : nil
    case .page:
      return RowBackground(style: .pageCard)
    case .sheet:
      return nil
    }
  }

  /// Concrete row backdrop so the background carries static type info instead of
  /// an `AnyView`. `rowBackground` returns `nil` for rows that want no custom
  /// background, which `.listRowBackground(nil)` resolves to the list default.
  struct RowBackground: View {
    enum Style {
      case sidebarPill(Color)  // inset accent pill behind the active sidebar/menu-bar row
      case pageCard  // uniform dark glass card on the page presentation
    }
    let style: Style

    var body: some View {
      switch style {
      case .sidebarPill(let accent):
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(accent.opacity(0.15))
          .padding(.horizontal, 10)
          .padding(.vertical, 2)
      case .pageCard:
        Rectangle().fill(.regularMaterial)
      }
    }
  }

  @ViewBuilder
  static func nowPlayingIndicator(
    isCurrent: Bool, isPlaying: Bool, accent: Color
  ) -> some View {
    if isCurrent {
      // Recreate on play/pause: the bars' repeatForever animations survive a
      // non-animated height change, so a stopped row would keep bouncing.
      EqualizerIcon(isPlaying: isPlaying, accent: accent)
        .id(isPlaying)
    }
  }
}

/// Equalizer indicator: a row of bars whose heights continuously tween up and
/// down (each on its own cadence, so they fall out of phase and read as live
/// audio levels). When paused they settle to a low resting height.
private struct EqualizerIcon: View {
  let isPlaying: Bool
  let accent: Color

  // Per-bar low/high fractions of the max height and oscillation duration. The
  // mismatched durations keep the bars from bouncing in lockstep.
  private struct Bar {
    let low: CGFloat
    let high: CGFloat
    let duration: Double
  }
  private static let bars: [Bar] = [
    Bar(low: 0.35, high: 1.0, duration: 0.50),
    Bar(low: 0.55, high: 0.8, duration: 0.38),
    Bar(low: 0.25, high: 0.95, duration: 0.62),
    Bar(low: 0.5, high: 0.7, duration: 0.46),
  ]

  private let barWidth: CGFloat = 2.5
  private let spacing: CGFloat = 2
  private let maxHeight: CGFloat = 12
  private let restHeight: CGFloat = 0.3

  @State private var peaked = false

  var body: some View {
    HStack(alignment: .bottom, spacing: spacing) {
      ForEach(Self.bars.indices, id: \.self) { index in
        let bar = Self.bars[index]
        Capsule()
          .fill(accent)
          .frame(width: barWidth, height: maxHeight * height(for: bar))
          .animation(
            isPlaying
              ? .easeInOut(duration: bar.duration).repeatForever(autoreverses: true)
              : .easeInOut(duration: 0.25),
            value: peaked)
      }
    }
    .frame(
      width: CGFloat(Self.bars.count) * barWidth + CGFloat(Self.bars.count - 1) * spacing,
      height: maxHeight, alignment: .bottom
    )
    // Kick off the perpetual oscillation; toggling `peaked` once is enough since
    // each bar's animation repeats forever (autoreversing between low and high).
    .onAppear { peaked = true }
    .accessibilityLabel(Text("Now Playing"))
  }

  private func height(for bar: Bar) -> CGFloat {
    guard isPlaying else { return restHeight }
    return peaked ? bar.high : bar.low
  }
}

struct PresetPickerRow: View {
  let preset: Preset
  let isEditMode: Bool
  let dismissOnSelect: Bool
  let presentation: LibraryView.Presentation
  let onSelection: (() -> Void)?
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  #if os(macOS)
    @ObservedObject private var appState = AppState.shared
  #endif
  @Environment(\.dismiss) private var dismiss

  init(
    preset: Preset, isEditMode: Bool, dismissOnSelect: Bool = true,
    presentation: LibraryView.Presentation = .sheet,
    onSelection: (() -> Void)? = nil
  ) {
    self.preset = preset
    self.isEditMode = isEditMode
    self.dismissOnSelect = dismissOnSelect
    self.presentation = presentation
    self.onSelection = onSelection
  }

  // The default preset is favorited under the shared "allSounds" token.
  private var starToken: String {
    preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
  }

  private var accent: Color {
    preset.accentColor ?? globalSettings.customAccentColor ?? .accentColor
  }

  /// This preset is the one currently driving playback (solo mode pre-empts it).
  private var isCurrent: Bool {
    audioManager.soloModeSound == nil && presetManager.currentPreset?.id == preset.id
  }

  /// macOS: Settings/About holds the detail pane, so any row click should
  /// dismiss it and reveal the preset — current row included (single click).
  private var settingsPaneShowing: Bool {
    #if os(macOS)
      return presentation == .sidebar && appState.showingSettingsPane
    #else
      return false
    #endif
  }

  /// The row's primary activation, shared by the pointer tap and the macOS
  /// VoiceOver action: apply the preset, or — on the current sidebar row —
  /// toggle play/pause. No-op while editing (taps belong to reorder/delete).
  private func activateRow() {
    guard !isEditMode else { return }
    #if os(macOS)
      if settingsPaneShowing {
        // Sub-page flags (About, Manage Sounds) reset via the pane's
        // onDisappear — clearing them here flashes the settings root.
        appState.showingSettingsPane = false
        if !isCurrent { applyPreset() }
        return
      }
    #endif
    if presentation == .sidebar && isCurrent {
      // Don't start a silent mix; pausing is always allowed.
      if audioManager.isGloballyPlaying || audioManager.hasSelectedSounds {
        audioManager.togglePlayback()
      }
    } else {
      applyPreset()
    }
  }

  var body: some View {
    HStack {
      // Tap target: applies the preset (disabled while editing, where taps
      // belong to reorder/delete).
      HStack(spacing: 10) {
        PresetThumbnail(
          artworkId: preset.artworkId,
          preset: preset,
          fallbackSystemImage: preset.isDefault ? "square.stack" : "music.note",
          tint: accent
        )
        .accessibilityHidden(true)

        Text(preset.displayName)
          .foregroundColor(
            LibraryRowStyle.titleColor(
              isCurrent: isCurrent, accent: accent, presentation: presentation))

        LibraryRowStyle.nowPlayingIndicator(
          isCurrent: isCurrent, isPlaying: audioManager.isGloballyPlaying,
          accent: accent)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      // Sidebar (iPad/macOS): the current row needs a double tap/click, which
      // toggles play–pause; elsewhere a single tap applies as usual.
      .onTapGesture(count: presentation == .sidebar && isCurrent && !settingsPaneShowing ? 2 : 1) {
        activateRow()
      }
      // Merge the row into a single element so VoiceOver exposes the tap as an
      // activation (an un-combined container drops the .onTapGesture action).
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(preset.displayName))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
      // macOS doesn't expose .onTapGesture as a VoiceOver activation, so the
      // .isButton trait announces a button that can't be activated. Represent it
      // as a real Button for assistive tech; iOS gets the action via .combine.
      #if os(macOS)
        .accessibilityRepresentation {
          Button(preset.displayName) { activateRow() }
          .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
      #endif

      // Always-visible favorite toggle (hidden in edit mode, where the reorder
      // handle takes the trailing edge).
      if !isEditMode {
        Button {
          globalSettings.toggleStarred(starToken)
        } label: {
          Image(systemName: globalSettings.isStarred(starToken) ? "star.fill" : "star")
            .foregroundStyle(
              globalSettings.isStarred(starToken)
                ? accent
                : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          globalSettings.isStarred(starToken)
            ? Text("Remove from Favorites") : Text("Add to Favorites"))
      }
    }
    .listRowBackground(
      LibraryRowStyle.rowBackground(
        isCurrent: isCurrent, accent: accent, presentation: presentation)
    )
  }

  private func applyPreset() {
    Task {
      do {
        // Exit solo/Quick Mix first so the previous mix doesn't briefly play.
        // Entering solo paused this preset's sounds without changing
        // `currentPreset`, so coming back to that same preset would hit
        // applyPreset's "already active" short-circuit and never resume them —
        // leaving everything silent. Force a re-apply when leaving solo.
        let wasSolo = audioManager.soloModeSound != nil
        if wasSolo {
          audioManager.exitSoloModeWithoutResuming()
        }
        if audioManager.isQuickMix {
          audioManager.exitQuickMix()
        }
        try presetManager.applyPreset(preset, forceReapply: wasSolo)
        OnboardingManager.shared.markPresetSwitched()
        if dismissOnSelect { dismiss() }
        onSelection?()
      } catch {
        Logger.ui.error("Error applying preset: \(error, privacy: .public)")
      }
    }
  }
}

/// A row that solos a single sound. Mirrors `PresetPickerRow`: tap to enter
/// solo mode, with an always-visible favorite star (a solo sound is starred
/// under the `solo:<fileName>` token).
struct SoloPickerRow: View {
  let sound: Sound
  let isEditMode: Bool
  let dismissOnSelect: Bool
  let presentation: LibraryView.Presentation
  let onSelection: (() -> Void)?
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  #if os(macOS)
    @ObservedObject private var appState = AppState.shared
  #endif
  @Environment(\.dismiss) private var dismiss

  init(
    sound: Sound, isEditMode: Bool, dismissOnSelect: Bool = true,
    presentation: LibraryView.Presentation = .sheet,
    onSelection: (() -> Void)? = nil
  ) {
    self.sound = sound
    self.isEditMode = isEditMode
    self.dismissOnSelect = dismissOnSelect
    self.presentation = presentation
    self.onSelection = onSelection
  }

  private var starToken: String {
    GlobalSettings.soloToken(forFileName: sound.fileName)
  }

  private var accent: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  private var isCurrent: Bool {
    audioManager.soloModeSound?.id == sound.id
  }

  /// macOS: Settings/About holds the detail pane, so any row click should
  /// dismiss it and reveal the solo sound — current row included (single click).
  private var settingsPaneShowing: Bool {
    #if os(macOS)
      return presentation == .sidebar && appState.showingSettingsPane
    #else
      return false
    #endif
  }

  /// The row's primary activation, shared by the pointer tap and the macOS
  /// VoiceOver action: solo the sound, or — on the current sidebar row — toggle
  /// play/pause. No-op while editing (taps belong to reorder/delete).
  private func activateRow() {
    guard !isEditMode else { return }
    #if os(macOS)
      if settingsPaneShowing {
        // Sub-page flags (About, Manage Sounds) reset via the pane's
        // onDisappear — clearing them here flashes the settings root.
        appState.showingSettingsPane = false
        if !isCurrent { soloSound() }
        return
      }
    #endif
    if presentation == .sidebar && isCurrent {
      audioManager.togglePlayback()
    } else {
      soloSound()
    }
  }

  var body: some View {
    HStack {
      HStack(spacing: 10) {
        PresetThumbnail(
          artworkId: nil,
          preset: nil,
          fallbackSystemImage: sound.systemIconName,
          tint: accent,
          isCircular: true
        )
        .accessibilityHidden(true)

        Text(sound.title)
          .foregroundColor(
            LibraryRowStyle.titleColor(
              isCurrent: isCurrent, accent: accent, presentation: presentation))

        LibraryRowStyle.nowPlayingIndicator(
          isCurrent: isCurrent, isPlaying: audioManager.isGloballyPlaying,
          accent: accent)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      // Sidebar (iPad/macOS): the current row needs a double tap/click, which
      // toggles play–pause; elsewhere a single tap applies as usual.
      .onTapGesture(count: presentation == .sidebar && isCurrent && !settingsPaneShowing ? 2 : 1) {
        activateRow()
      }
      // Merge the row into a single element so VoiceOver exposes the tap as an
      // activation (an un-combined container drops the .onTapGesture action).
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(sound.title))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
      // macOS doesn't expose .onTapGesture as a VoiceOver activation, so the
      // .isButton trait announces a button that can't be activated. Represent it
      // as a real Button for assistive tech; iOS gets the action via .combine.
      #if os(macOS)
        .accessibilityRepresentation {
          Button(sound.title) { activateRow() }
          .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
      #endif

      if !isEditMode {
        Button {
          globalSettings.toggleStarred(starToken)
        } label: {
          Image(systemName: globalSettings.isStarred(starToken) ? "star.fill" : "star")
            .foregroundStyle(
              globalSettings.isStarred(starToken)
                ? accent
                : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          globalSettings.isStarred(starToken)
            ? Text("Remove from Favorites") : Text("Add to Favorites"))
      }
    }
    .listRowBackground(
      LibraryRowStyle.rowBackground(
        isCurrent: isCurrent, accent: accent, presentation: presentation)
    )
  }

  private func soloSound() {
    // Tapping the sound that's already soloing shouldn't stop it — that would be
    // a surprising "toggle off". Just close the sheet (iPhone) or do nothing
    // (sidebar), leaving playback untouched.
    if isCurrent {
      if dismissOnSelect { dismiss() }
      onSelection?()
      return
    }
    Task { @MainActor in
      audioManager.toggleSoloMode(for: sound)
      if dismissOnSelect { dismiss() }
      onSelection?()
    }
  }
}

struct LibraryView: View {
  /// Where this Library is rendered. As a `.page` (iPhone) it's the ROOT of
  /// the mixer's `NavigationStack` — the mixer is pushed on top of it, so
  /// selecting a row navigates forward to the mixer via `onSelection`. As a
  /// `.sidebar` (iPad) it relies on the enclosing `NavigationSplitView` for
  /// the nav bar and stays put when a row is tapped. As a `.sheet` it's a
  /// self-contained modal with its own `NavigationStack` and close button.
  enum Presentation {
    case sheet
    case sidebar
    case page
    case menuBar
  }

  var presentation: Presentation = .sheet
  /// Opens the full Settings sheet from the leading toolbar gear (iPhone page
  /// and iPad sidebar alike). nil in the sheet presentation, where Settings
  /// isn't surfaced here.
  var onOpenSettings: (() -> Void)?
  /// Page-only: called after a row applies its selection so the owner can
  /// navigate forward to the mixer (the Library is the stack root, so there
  /// is nothing to dismiss).
  var onSelection: (() -> Void)?
  /// Page-only: the current preset's background artwork (loaded by the
  /// mixer), reused here so the Library shares Now Playing's backdrop.
  var backgroundImage: PlatformImage?
  /// Page-only: measured height of the stack's Now Playing bar. The bar's
  /// `safeAreaBar` doesn't inset this root list, so the list reserves this much
  /// bottom margin to clear it — derived, not hardcoded, so it tracks Dynamic
  /// Type and device safe areas.
  var bottomBarHeight: CGFloat = 0

  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var onboardingManager = OnboardingManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  // Re-filter the Sounds section when per-sound customizations change
  // (preset-use-only, loop, renames) — they live outside the audio manager.
  @ObservedObject private var customizationManager = SoundCustomizationManager.shared
  @State private var showingNewPresetSheet = false
  @State private var presetToDelete: Preset?
  @State private var isEditMode = false
  @State private var showingSoundFilePicker = false
  @State private var importedSoundURL: URL?
  @State private var showingImportSoundSheet = false
  #if os(macOS)
    @State private var selectedPresetForEdit: Preset?
  #endif
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  // TipKit tips
  private let createFirstPresetTip = CreateFirstPresetTip()
  private let switchPresetsTip = SwitchPresetsTip()

  private var sortedCustomPresets: [Preset] {
    presetManager.presets
      .filter { !$0.isDefault }
      .sorted {
        let order1 = $0.order ?? Int.max
        let order2 = $1.order ?? Int.max
        return order1 < order2
      }
  }

  /// Non-favorited sounds, alphabetical by title, for the fixed Sounds (solo)
  /// section. Favorited sounds appear in the Favorites section instead — the
  /// same split presets use, so nothing shows twice. Preset-use-only sounds
  /// don't solo and stay out entirely.
  private var soloSounds: [Sound] {
    audioManager.sounds
      .filter { !$0.isPresetUseOnly }
      .filter { !globalSettings.isStarred(GlobalSettings.soloToken(forFileName: $0.fileName)) }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  // MARK: - Favorites / Presets model

  /// Favorited tokens in saved order, dropping any whose preset no longer exists.
  private var favoriteTokens: [String] {
    globalSettings.starredItems.filter { token in
      if audioManager.sound(forSoloToken: token) != nil { return true }
      switch token {
      case GlobalSettings.allSoundsToken: return presetManager.presets.contains { $0.isDefault }
      default: return presetManager.presets.contains { $0.id.uuidString == token }
      }
    }
  }

  /// Non-favorited custom presets in saved order. All Blankie Sounds and Quick
  /// Mix render as fixed rows in the Presets section, NOT in this list — so
  /// the reorderable ForEach contains only reorderable customs.
  private var nonFavoriteCustomTokens: [String] {
    sortedCustomPresets.map(\.id.uuidString).filter { !globalSettings.isStarred($0) }
  }

  /// Show All Blankie Sounds as a fixed row in the Presets section only when it
  /// isn't favorited (when favorited it appears in the Favorites section instead).
  private var showsDefaultInAllPresets: Bool {
    presetManager.presets.contains { $0.isDefault }
      && !globalSettings.isStarred(GlobalSettings.allSoundsToken)
  }

  // MARK: - Favorite ordering & deletion
  //
  // Single source of truth: `starredItems`. Favoriting is a star tap on the
  // row; reordering is standard edit-mode `.onMove` within Favorites.

  private func reorderFavorites(from offsets: IndexSet, to destination: Int) {
    var tokens = favoriteTokens
    tokens.move(fromOffsets: offsets, toOffset: destination)
    // Preserve any starred tokens not currently shown (e.g. a preset still
    // loading) so reordering never silently drops a favorite.
    let shown = Set(favoriteTokens)
    let preserved = globalSettings.starredItems.filter { !shown.contains($0) }
    globalSettings.setStarredItems(tokens + preserved)
  }

  /// Only custom presets can be deleted (not All Blankie Sounds).
  private func isDeletable(_ token: String) -> Bool {
    presetManager.presets.contains { $0.id.uuidString == token && !$0.isDefault }
  }

  private func requestDelete(_ token: String) {
    if let preset = presetManager.presets.first(where: { $0.id.uuidString == token }),
      !preset.isDefault
    {
      presetToDelete = preset
    }
  }

  // These lists only ever produce single-offset deletes (swipe / edit-mode −),
  // and deletion routes through one confirmation alert, so handle a single row.
  private func deleteFavorites(at offsets: IndexSet) {
    if let index = offsets.first, favoriteTokens.indices.contains(index) {
      requestDelete(favoriteTokens[index])
    }
  }

  private func deleteAllPresets(at offsets: IndexSet) {
    if let index = offsets.first, nonFavoriteCustomTokens.indices.contains(index) {
      requestDelete(nonFavoriteCustomTokens[index])
    }
  }

  /// Reorder the non-favorited custom presets, persisting their master `order`.
  private func reorderAllPresets(from offsets: IndexSet, to destination: Int) {
    var tokens = nonFavoriteCustomTokens
    tokens.move(fromOffsets: offsets, toOffset: destination)
    applyCustomOrder(tokens)
  }

  /// Persist a collision-free `order` across ALL custom presets: favorited
  /// customs (in favorites order) first, then the reordered non-favorited ones.
  /// Ordering the full set avoids leaving favorited presets with stale `order`
  /// values that collide with the new sequence.
  private func applyCustomOrder(_ reorderedNonFavoriteIDs: [String]) {
    // Only real custom presets carry an `order`; drop All Blankie Sounds and
    // solo-sound tokens, which aren't part of the custom-preset ordering.
    let customIDs = Set(sortedCustomPresets.map(\.id.uuidString))
    let favoritedCustomIDs = favoriteTokens.filter { customIDs.contains($0) }
    let fullOrder = favoritedCustomIDs + reorderedNonFavoriteIDs
    let orderByID = Dictionary(uniqueKeysWithValues: fullOrder.enumerated().map { ($1, $0) })
    var presets = presetManager.presets
    for index in presets.indices {
      if let newOrder = orderByID[presets[index].id.uuidString] {
        presets[index].order = newOrder
      }
    }
    presetManager.setPresets(presets)
    presetManager.savePresets()
  }

  // MARK: - Row builders

  /// As a sheet, selecting a row dismisses the Library; as the root page it
  /// navigates forward to the mixer via `onSelection`; as a sidebar it stays
  /// put. Rows gate their own `dismiss()` on `dismissOnSelect` — only the
  /// sheet has anything to dismiss.
  private var dismissOnSelect: Bool { presentation == .sheet }
  private var onSelect: (() -> Void)? {
    switch presentation {
    case .sheet: return { dismiss() }
    case .page, .menuBar: return onSelection
    case .sidebar: return nil
    }
  }

  // MARK: - Page backdrop

  /// Now Playing's accent rule: the preset accent, except solo mode (and any
  /// preset-less state), which uses the app accent.
  private var pageAccent: Color {
    if audioManager.soloModeSound != nil {
      return globalSettings.customAccentColor ?? .accentColor
    }
    return presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
      ?? .accentColor
  }

  /// Page-only backdrop mirroring Now Playing: a black base with the preset's
  /// blurred artwork, falling back to an accent gradient (solo and Quick Mix
  /// always use the gradient, like Now Playing does).
  private var pageBackground: some View {
    Color.black
      .overlay {
        if audioManager.soloModeSound == nil && !audioManager.isQuickMix,
          let image = backgroundImage
        {
          #if os(macOS)
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .blur(radius: 40)
              .opacity(0.4)
          #else
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .blur(radius: 40)
              .opacity(0.4)
          #endif
        } else {
          LinearGradient(
            colors: [
              pageAccent.opacity(0.6),
              pageAccent.opacity(0.3),
              Color.black.opacity(0.8),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        }
      }
      .clipped()
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func tokenRow(_ token: String) -> some View {
    if let sound = audioManager.sound(forSoloToken: token) {
      SoloPickerRow(
        sound: sound, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
        presentation: presentation, onSelection: onSelect)
    } else {
      switch token {
      case GlobalSettings.allSoundsToken:
        if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
          PresetPickerRow(
            preset: defaultPreset, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
            presentation: presentation, onSelection: onSelect)
        }
      default:
        if let preset = presetManager.presets.first(where: { $0.id.uuidString == token }) {
          let row = PresetPickerRow(
            preset: preset, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
            presentation: presentation, onSelection: onSelect)
          #if os(macOS)
            // macOS rename/delete replacing the old PresetPicker's per-row pencil
            // and trash. Custom presets only — never the default or solo rows.
            row.contextMenu {
              Button("Edit Preset…") { selectedPresetForEdit = preset }
              Button("Delete Preset…", role: .destructive) { presetToDelete = preset }
            }
          #else
            row
          #endif
        }
      }
    }
  }

  private var quickMixRow: some View {
    let accent = globalSettings.customAccentColor ?? .accentColor
    return Button {
      Task { @MainActor in
        if audioManager.soloModeSound != nil {
          audioManager.exitSoloModeWithoutResuming()
        }
        if !audioManager.isQuickMix {
          audioManager.enterQuickMix()
          OnboardingManager.shared.markQuickMixUsed()
        }
        onSelect?()
      }
    } label: {
      HStack(spacing: 10) {
        PresetThumbnail(
          artworkId: nil,
          preset: nil,
          fallbackSystemImage: "square.grid.2x2",
          tint: accent
        )
        .accessibilityHidden(true)
        Text("Quick Mix")
          .foregroundColor(
            LibraryRowStyle.titleColor(
              isCurrent: audioManager.isQuickMix, accent: accent, presentation: presentation))
        Spacer()
        LibraryRowStyle.nowPlayingIndicator(
          isCurrent: audioManager.isQuickMix, isPlaying: audioManager.isGloballyPlaying,
          accent: accent)
      }
    }
    .accessibilityAddTraits(audioManager.isQuickMix ? [.isSelected] : [])
    .listRowBackground(
      LibraryRowStyle.rowBackground(
        isCurrent: audioManager.isQuickMix, accent: accent, presentation: presentation))
  }

  /// The Add menu's items (New Preset / Import), shared by the iOS and macOS
  /// toolbar branches so the actions aren't duplicated.
  @ViewBuilder
  private var addMenuContent: some View {
    Button {
      showingNewPresetSheet = true
    } label: {
      Label("New Preset", systemImage: "rectangle.stack.badge.plus")
    }
    Button {
      showingSoundFilePicker = true
    } label: {
      Label("Import", systemImage: "square.and.arrow.down")
    }
  }

  var body: some View {
    Group {
      switch presentation {
      case .sheet:
        // A self-contained modal with its own nav bar + close button.
        NavigationStack { libraryList }
      case .sidebar:
        // iPad: the enclosing NavigationSplitView supplies the nav bar.
        libraryList
      case .page:
        // iPhone: the enclosing NavigationStack supplies the nav bar. The
        // list sits on Now Playing's backdrop instead of the system grouped
        // gray, with a dark bar scheme so its controls stay legible over it.
        libraryList
          .scrollContentBackground(.hidden)
          .background { pageBackground }
          // Reserve the measured Now Playing bar height (plus a little breathing
          // room) so the last row clears it — the stack's safeAreaBar doesn't
          // inset this root list.
          .contentMargins(.bottom, bottomBarHeight + 8, for: .scrollContent)
          #if os(iOS) || os(visionOS)
            .toolbarColorScheme(.dark, for: .navigationBar)
          #endif
      case .menuBar:
        // Sidebar list style so the highlight pill and section headers match the
        // main window's sidebar, on the popover's own material.
        libraryList
          .scrollContentBackground(.hidden)
          .listStyle(.sidebar)
      }
    }
    // Carry the app accent into the sheet explicitly. A presented sheet doesn't
    // reliably keep the tint it inherited at presentation across later
    // re-renders (e.g. favoriting a row or toggling Edit), so the row icons and
    // checkmarks — which use `.accentColor` — would snap back to the system blue
    // while the stars (which read `customAccentColor` directly) stayed tinted.
    // Setting the tint locally on the sheet's own hierarchy keeps them in sync.
    .tint(globalSettings.customAccentColor ?? .accentColor)
  }

  @ViewBuilder
  private var libraryList: some View {
    List {
      if !presetManager.hasCustomPresets {
        TipView(createFirstPresetTip, arrowEdge: .top) { action in
          if action.id == "create" {
            showingNewPresetSheet = true
          } else if action.id == "dismiss" {
            // TipKit actions don't auto-dismiss; invalidate explicitly.
            createFirstPresetTip.invalidate(reason: .actionPerformed)
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }

      if presetManager.isLoading {
        HStack {
          Spacer()
          ProgressView("Loading Presets...")
          Spacer()
        }
        .padding()
      } else if presetManager.presets.isEmpty {
        HStack {
          Spacer()
          VStack(spacing: 12) {
            Image(systemName: "star.circle")
              .font(.system(size: 48))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)

            Text("No Custom Presets")
              .font(.headline)

            Text(
              "Save your current sound configuration as a preset to quickly access it later."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          }
          .padding()
          .frame(maxWidth: 250)
          Spacer()
        }
        .listRowBackground(Color.clear)
      } else {
        // FAVORITES — tap a row's star to add/remove; reorder via Edit.
        Section {
          if favoriteTokens.isEmpty {
            Text(
              "Tap the star on any preset to add it here."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // Match the picker rows' glass on the page (nil elsewhere, keeping
            // the default background).
            .listRowBackground(
              LibraryRowStyle.rowBackground(
                isCurrent: false, accent: .clear, presentation: presentation))
          } else {
            ForEach(favoriteTokens, id: \.self) { token in
              tokenRow(token)
                .deleteDisabled(!isDeletable(token))
            }
            .onMove(perform: reorderFavorites)
            .onDelete(perform: deleteFavorites)
          }
        } header: {
          Text("Favorites")
        }

        // ALL PRESETS — Quick Mix and All Blankie Sounds are fixed rows at the
        // top; only the custom presets below are reorderable in Edit.
        Section {
          // Quick Mix — not favoritable (its own thing); iOS/iPadOS only.
          #if !os(macOS)
            quickMixRow
          #endif

          if showsDefaultInAllPresets {
            tokenRow(GlobalSettings.allSoundsToken)
          }

          ForEach(nonFavoriteCustomTokens, id: \.self) { token in
            tokenRow(token)
          }
          .onMove(perform: reorderAllPresets)
          .onDelete(perform: deleteAllPresets)
        } header: {
          Text("Presets")
        }

        // SOUNDS — solo a single sound. Listed alphabetically and fixed
        // (not reorderable); tap the star to favorite a sound.
        Section {
          ForEach(soloSounds, id: \.id) { sound in
            SoloPickerRow(
              sound: sound, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
              presentation: presentation, onSelection: onSelect)
          }
        } header: {
          Text("Sounds")
        }
      }
    }
    // The iPhone page is the app's root screen, so it titles as "Blankie";
    // the (currently unused) sheet keeps "Library"; the sidebar is
    // self-evidently the library, so it omits the title to leave the bar for
    // the controls.
    .navigationTitle(
      {
        switch presentation {
        case .sidebar: return Text(verbatim: "")
        case .page: return Text(verbatim: "Blankie")
        case .sheet, .menuBar: return Text("Library")
        }
      }()
    )
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    #if os(iOS)
      .toolbar {
        // The close button only makes sense in the sheet; the sidebar is
        // always present, so it has nothing to dismiss.
        if presentation == .sheet {
          ToolbarItem(placement: .topBarLeading) {
            // Standard close affordance: HIG advises against a text "Close"
            // label in favor of the familiar close symbol.
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            // Monochrome to match the system sidebar toggle (which ignores tint);
            // the accent stays in content, not the bar chrome.
            .tint(Color.primary)
            .accessibilityLabel(Text("Close"))
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if presetManager.hasCustomPresets {
            Button {
              isEditMode.toggle()
            } label: {
              Text(isEditMode ? "Done" : "Edit")
            }
            .tint(Color.primary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if !isEditMode {
            Menu {
              addMenuContent
            } label: {
              Label("Add", systemImage: "plus")
            }
            .tint(Color.primary)
          }
        }
        // Settings gear, opening the Settings sheet. Leading in both
        // presentations so iPhone and iPad match; the sidebar's trailing
        // edge holds the system sidebar toggle plus Edit/Add.
        if let onOpenSettings {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              onOpenSettings()
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
            .tint(Color.primary)
          }
        }
      }
    #endif
    #if os(macOS)
      // The sidebar's window toolbar carries only the Add menu; the system
      // adds the sidebar-toggle item automatically. No Edit toggle (reorder
      // works via drag); Settings is the sidebar's footer gear. (The menu bar
      // popover has no toolbar surface — it reaches Settings via its own "⋯"
      // header menu, not here.)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            addMenuContent
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
    #endif
    #if os(iOS)
      .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
    #endif
    // Page-only: the always-dark reading Now Playing uses, so row text stays
    // legible over the dark backdrop. Applied here — inside the sheet/alert
    // modifiers — so presented sheets keep the system appearance.
    .environment(\.colorScheme, presentation == .page ? .dark : systemColorScheme)
    .sheet(isPresented: $showingNewPresetSheet) {
      CreatePresetSheet(isPresented: $showingNewPresetSheet)
    }
    .fileImporter(
      isPresented: $showingSoundFilePicker,
      allowedContentTypes: [.audio, .blankiePreset],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      // A .blankie file is a preset archive — hand it to the importer, which
      // detects the type and imports it as a preset. Anything else is audio →
      // preselect it in the add-sound sheet.
      if url.pathExtension.lowercased() == "blankie" {
        AudioFileImporter.shared.handleIncomingFile(url)
      } else {
        // Stage an app-owned copy so previewing the not-yet-saved sound can
        // load it after the picker's security scope ends.
        importedSoundURL = AudioFileImporter.shared.stagedTempCopy(of: url)
        showingImportSoundSheet = importedSoundURL != nil
      }
    }
    .sheet(isPresented: $showingImportSoundSheet) {
      if let url = importedSoundURL {
        SoundSheet(mode: .add, preselectedFile: url)
      }
    }
    #if os(macOS)
      .sheet(item: $selectedPresetForEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $selectedPresetForEdit)
      }
    #endif
    .alert(
      "Delete Preset",
      isPresented: .init(
        get: { presetToDelete != nil },
        set: { if !$0 { presetToDelete = nil } }
      )
    ) {
      Button("Cancel", role: .cancel) {
        presetToDelete = nil
      }

      Button("Delete", role: .destructive) {
        if let preset = presetToDelete {
          Task {
            presetManager.deletePreset(preset)
            presetToDelete = nil
          }
        }
      }
    } message: {
      if let preset = presetToDelete {
        Text(
          "Are you sure you want to delete '\(preset.name)'? This action cannot be undone."
        )
      }
    }
  }
}

/// CarPlay-style leading artwork tile for picker rows. Loads the preset's
/// saved artwork asynchronously (cached by `PresetArtworkManager`); when there
/// is no artwork — solo sounds, Quick Mix, or a preset without a custom image —
/// it shows the supplied glyph on a faintly tinted tile so every row keeps
/// the same leading footprint. Presets and Quick Mix use a squircle; sound
/// rows use a circle to read as a different kind of item.
struct PresetThumbnail: View {
  let artworkId: UUID?
  let preset: Preset?
  let fallbackSystemImage: String
  let tint: Color
  var isCircular = false

  @Environment(\.displayScale) private var displayScale
  @State private var image: PlatformImage?

  private let size: CGFloat = 32
  private var shape: AnyShape {
    isCircular
      ? AnyShape(Circle())
      : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  var body: some View {
    Group {
      if let image {
        platformImage(image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        shape
          .fill(tint.opacity(0.15))
          .overlay {
            Image(systemName: fallbackSystemImage)
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(tint)
          }
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    // strokeBorder needs a concrete InsettableShape, which AnyShape isn't.
    .overlay {
      if isCircular {
        Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
      }
    }
    .task(
      id:
        "\(artworkId?.uuidString ?? "nil")-\(preset?.animatedArtwork?.squarePreviewPath ?? preset?.animatedArtwork?.previewPath ?? "nil")"
    ) {
      if let artworkId {
        image = await PresetArtworkManager.shared.loadThumbnail(
          id: artworkId, maxPixelSize: size * displayScale)
      } else if let preset, preset.animatedArtwork != nil {
        // No static artwork — fall back to the animated artwork's preview image,
        // the same art the mixer / Now Playing / lock screen show.
        image = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
      } else {
        image = nil
      }
    }
  }

  private func platformImage(_ img: PlatformImage) -> Image {
    #if os(macOS)
      Image(nsImage: img)
    #else
      Image(uiImage: img)
    #endif
  }
}

// Preview Provider
struct LibraryView_Previews: PreviewProvider {
  static var previews: some View {
    LibraryView()
  }
}
