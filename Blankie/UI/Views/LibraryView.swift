//
//  LibraryView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os

/// Shared "now playing" treatment for Library rows: accent title, equalizer
/// glyph, and a highlight on sidebar rows.
enum LibraryRowStyle {
  static func titleColor(
    isCurrent: Bool, accent: Color, presentation: LibraryView.Presentation
  ) -> Color {
    let tints = presentation == .sidebar || presentation == .menuBar || presentation == .page
    return tints && isCurrent ? accent : .primary
  }

  /// Sidebar: an accent pill behind the active row. Page: a material card on
  /// every row. `nil` keeps the list's default background.
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

  /// A concrete view type so `rowBackground` can avoid `AnyView`.
  struct RowBackground: View {
    enum Style {
      case sidebarPill(Color)
      case pageCard
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

/// Animated equalizer bars, each on its own cadence. Paused, they settle low.
private struct EqualizerIcon: View {
  let isPlaying: Bool
  let accent: Color

  // Fractions of max height. Mismatched durations keep the bars out of step.
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
    // One toggle starts the repeating, autoreversing animation.
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
  private let presetManager = PresetManager.shared
  private let audioManager = AudioManager.shared
  private let globalSettings = GlobalSettings.shared
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
    // The iPhone page keeps every row on the app accent. Elsewhere rows use
    // their preset's accent.
    if presentation == .page {
      return globalSettings.customAccentColor ?? .accentColor
    }
    return preset.accentColor ?? globalSettings.customAccentColor ?? .accentColor
  }

  /// Single-sound mode takes precedence over the current preset.
  private var isCurrent: Bool {
    audioManager.singleSound == nil && presetManager.currentPreset?.id == preset.id
  }

  /// macOS: while Settings holds the detail pane, any single click (current row
  /// included) closes it and shows the preset.
  private var settingsPaneShowing: Bool {
    #if os(macOS)
      return presentation == .sidebar && appState.showingSettingsPane
    #else
      return false
    #endif
  }

  /// Shared by the tap and the macOS VoiceOver action. The current sidebar row
  /// toggles play/pause. Other rows apply the preset.
  private func activateRow() {
    guard !isEditMode else { return }
    #if os(macOS)
      if settingsPaneShowing {
        // The pane's onDisappear resets the sub-page flags.
        appState.showingSettingsPane = false
        if !isCurrent { applyPreset() }
        return
      }
    #endif
    if presentation == .sidebar && isCurrent {
      // Don't start a silent mix. Pausing is always allowed.
      if audioManager.isGloballyPlaying || audioManager.hasSelectedSounds {
        audioManager.togglePlayback()
      }
    } else {
      applyPreset()
    }
  }

  var body: some View {
    HStack {
      HStack(spacing: 10) {
        PresetThumbnail(
          artworkId: preset.artworkId,
          preset: preset,
          fallbackSystemImage: preset.isDefault ? "square.stack" : "music.note",
          tint: accent,
          compositeIcons: preset.isDefault
            ? nil : AudioManager.shared.compositeSoundIcons(for: preset),
          useBrand: preset.isDefault
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
      // The current sidebar row needs a double tap or click to toggle play/pause.
      .onTapGesture(count: presentation == .sidebar && isCurrent && !settingsPaneShowing ? 2 : 1) {
        activateRow()
      }
      // Combined so VoiceOver exposes the tap gesture as an activation on iOS.
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(preset.displayName))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
      // macOS VoiceOver can't activate .onTapGesture, so expose a real Button.
      #if os(macOS)
        .accessibilityRepresentation {
          Button(preset.displayName) { activateRow() }
          .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
      #endif

      // Edit mode gives the trailing edge to the reorder handle.
      if !isEditMode {
        Button {
          globalSettings.toggleStarred(starToken)
        } label: {
          Image(systemName: globalSettings.isStarred(starToken) ? "star.fill" : "star")
            .foregroundStyle(
              globalSettings.isStarred(starToken)
                // The app accent, ignoring the preset's own accent.
                ? globalSettings.customAccentColor ?? .accentColor
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
        // Single sound pauses the preset's sounds but keeps `currentPreset`, so
        // returning to the same preset has to force a re-apply.
        let wasSingle = audioManager.singleSound != nil
        audioManager.leaveTransientModes()
        try presetManager.applyPreset(preset, forceReapply: wasSingle)
        if dismissOnSelect { dismiss() }
        onSelection?()
      } catch {
        Logger.ui.error("Error applying preset: \(error, privacy: .public)")
      }
    }
  }
}

/// A row that plays a single sound. Mirrors `PresetPickerRow`. The star uses
/// the `solo:<fileName>` token.
struct SingleSoundPickerRow: View {
  let sound: Sound
  let isEditMode: Bool
  let dismissOnSelect: Bool
  let presentation: LibraryView.Presentation
  let onSelection: (() -> Void)?
  private let audioManager = AudioManager.shared
  private let globalSettings = GlobalSettings.shared
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
    PlayableItem.single(fileName: sound.fileName).token
  }

  private var accent: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  private var isCurrent: Bool {
    audioManager.singleSound?.id == sound.id
  }

  /// macOS: while Settings holds the detail pane, any single click (current row
  /// included) closes it and shows the sound.
  private var settingsPaneShowing: Bool {
    #if os(macOS)
      return presentation == .sidebar && appState.showingSettingsPane
    #else
      return false
    #endif
  }

  /// Shared by the tap and the macOS VoiceOver action. The current sidebar row
  /// toggles play/pause. Other rows play their sound on its own.
  private func activateRow() {
    guard !isEditMode else { return }
    #if os(macOS)
      if settingsPaneShowing {
        // The pane's onDisappear resets the sub-page flags.
        appState.showingSettingsPane = false
        if !isCurrent { playOnItsOwn() }
        return
      }
    #endif
    if presentation == .sidebar && isCurrent {
      audioManager.togglePlayback()
    } else {
      playOnItsOwn()
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

        Text(sound.localizedTitle)
          .foregroundColor(
            LibraryRowStyle.titleColor(
              isCurrent: isCurrent, accent: accent, presentation: presentation))

        LibraryRowStyle.nowPlayingIndicator(
          isCurrent: isCurrent, isPlaying: audioManager.isGloballyPlaying,
          accent: accent)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      // The current sidebar row needs a double tap or click to toggle play/pause.
      .onTapGesture(count: presentation == .sidebar && isCurrent && !settingsPaneShowing ? 2 : 1) {
        activateRow()
      }
      // Combined so VoiceOver exposes the tap gesture as an activation on iOS.
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(sound.localizedTitle))
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
      // macOS VoiceOver can't activate .onTapGesture, so expose a real Button.
      #if os(macOS)
        .accessibilityRepresentation {
          Button(sound.localizedTitle) { activateRow() }
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

  private func playOnItsOwn() {
    // Tapping the current single sound leaves playback alone.
    if isCurrent {
      if dismissOnSelect { dismiss() }
      onSelection?()
      return
    }
    Task { @MainActor in
      audioManager.toggleSingleSound(for: sound)
      if dismissOnSelect { dismiss() }
      onSelection?()
    }
  }
}

struct LibraryView: View {
  /// `.page`: the iPhone stack's root. A selection pushes the mixer.
  /// `.sidebar`: inside a `NavigationSplitView`. It stays put on selection.
  /// `.sheet`: a self-contained modal with its own stack and close button.
  enum Presentation {
    case sheet
    case sidebar
    case page
    case menuBar
  }

  var presentation: Presentation = .sheet
  /// Leading toolbar gear. nil in the sheet presentation.
  var onOpenSettings: (() -> Void)?
  /// Page-only: lets the owner push the mixer after a selection.
  var onSelection: (() -> Void)?
  /// Page-only: measured Now Playing bar height. The stack's `safeAreaBar`
  /// doesn't inset this root list, so it reserves the margin itself.
  var bottomBarHeight: CGFloat = 0

  private let presetManager = PresetManager.shared
  private let audioManager = AudioManager.shared
  @ObservedObject private var onboardingManager = OnboardingManager.shared
  private let globalSettings = GlobalSettings.shared
  private var hasUnseenWhatsNew: Bool {
    WhatsNew.hasUnseen(lastSeen: globalSettings.lastSeenWhatsNewVersion)
  }
  // Observed so the Sounds section updates when per-sound customizations change.
  private let customizationManager = SoundCustomizationManager.shared
  @State private var showingNewPresetSheet = false
  @State private var presetToDelete: Preset?
  @State private var isEditMode = false
  @State private var showingSoundFilePicker = false
  @State private var importedSoundURL: URL?
  @State private var showingImportSoundSheet = false
  @State private var selectedPresetForEdit: Preset?
  @State private var soundToEdit: Sound?
  @State private var soundToDelete: Sound?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  private var sortedCustomPresets: [Preset] {
    presetManager.presets
      .filter { !$0.isDefault }
      .sorted {
        let order1 = $0.order ?? Int.max
        let order2 = $1.order ?? Int.max
        return order1 < order2
      }
  }

  /// Non-favorited sounds, alphabetical. Favorites show in their own section.
  /// Preset-use-only sounds can't play on their own.
  private var singleSounds: [Sound] {
    audioManager.sounds
      .filter { !$0.isPresetUseOnly }
      .filter { !globalSettings.isStarred(PlayableItem.single(fileName: $0.fileName).token) }
      .sortedByLocalizedTitle()
  }

  // MARK: - Favorites / Presets model

  /// Favorited tokens in saved order, dropping any whose preset no longer exists.
  private var favoriteTokens: [String] {
    globalSettings.starredItems.filter { token in
      if audioManager.sound(forSingleToken: token) != nil { return true }
      switch token {
      case GlobalSettings.allSoundsToken: return presetManager.presets.contains { $0.isDefault }
      default: return presetManager.presets.contains { $0.id.uuidString == token }
      }
    }
  }

  /// Non-favorited custom presets in saved order. All Blankie Sounds and Quick
  /// Mix are fixed rows outside this reorderable list.
  private var nonFavoriteCustomTokens: [String] {
    sortedCustomPresets.map(\.id.uuidString).filter { !globalSettings.isStarred($0) }
  }

  /// All Blankie Sounds sits in Presets unless it's favorited.
  private var showsDefaultInAllPresets: Bool {
    presetManager.presets.contains { $0.isDefault }
      && !globalSettings.isStarred(GlobalSettings.allSoundsToken)
  }

  // MARK: - Favorite ordering & deletion

  private func reorderFavorites(from offsets: IndexSet, to destination: Int) {
    var tokens = favoriteTokens
    tokens.move(fromOffsets: offsets, toOffset: destination)
    // Keep starred tokens that aren't shown (a preset still loading, say).
    let shown = Set(favoriteTokens)
    let preserved = globalSettings.starredItems.filter { !shown.contains($0) }
    globalSettings.setStarredItems(tokens + preserved)
  }

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

  // Swipe and edit-mode deletes are single rows, confirmed by one alert.
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

  /// Only custom sounds can be deleted.
  private func deleteSounds(at offsets: IndexSet) {
    if let index = offsets.first, singleSounds.indices.contains(index),
      singleSounds[index].isCustom
    {
      soundToDelete = singleSounds[index]
    }
  }

  private func deleteCustomSound(_ sound: Sound) {
    guard sound.isCustom,
      let id = sound.customSoundDataID,
      let record = CustomSoundManager.shared.getCustomSound(by: id)
    else { return }
    if case .failure(let error) = CustomSoundManager.shared.deleteCustomSound(record) {
      Logger.ui.error("LibraryView: Failed to delete custom sound: \(error, privacy: .public)")
      return
    }
    // Drop only the deleted sound (a full reload strands single sound/preview/Quick Mix instances).
    AudioManager.shared.syncCustomSounds()
  }

  private func reorderAllPresets(from offsets: IndexSet, to destination: Int) {
    var tokens = nonFavoriteCustomTokens
    tokens.move(fromOffsets: offsets, toOffset: destination)
    applyCustomOrder(tokens)
  }

  /// Renumbers every custom preset (favorites first, in favorites order) so no
  /// two share an `order` value.
  private func applyCustomOrder(_ reorderedNonFavoriteIDs: [String]) {
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

  /// Only the sheet has anything to dismiss.
  private var dismissOnSelect: Bool { presentation == .sheet }
  private var onSelect: (() -> Void)? {
    switch presentation {
    case .sheet: return { dismiss() }
    case .page, .menuBar: return onSelection
    case .sidebar: return nil
    }
  }

  // MARK: - Page backdrop

  /// Page-only backdrop. Always the app accent, never the playing preset's
  /// artwork or accent.
  private var pageBackground: some View {
    let accent = globalSettings.customAccentColor ?? .accentColor
    return Color.black
      .overlay {
        LinearGradient(
          colors: [
            accent.opacity(0.6),
            accent.opacity(0.3),
            Color.black.opacity(0.8),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func tokenRow(_ token: String) -> some View {
    switch PlayableItem(token: token) {
    case .single(let fileName):
      if let sound = audioManager.sound(fileName: fileName) {
        singleRow(sound)
      }
    case .allSounds:
      if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
        PresetPickerRow(
          preset: defaultPreset, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
          presentation: presentation, onSelection: onSelect)
      }
    case .preset(let id):
      if let preset = presetManager.presets.first(where: { $0.id == id }) {
        let row = PresetPickerRow(
          preset: preset, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
          presentation: presentation, onSelection: onSelect)
        // Edit and delete: a context menu on macOS, a trailing swipe on iOS.
        #if os(macOS)
          row.contextMenu {
            Button("Edit Preset…") { selectedPresetForEdit = preset }
            Button("Delete Preset…", role: .destructive) { presetToDelete = preset }
          }
        #else
          row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
              presetToDelete = preset
            } label: {
              Label("Delete", systemImage: "trash")
            }
            // Clears the inherited accent so the destructive red shows.
            .tint(nil)
            Button {
              selectedPresetForEdit = preset
            } label: {
              Label("Edit", systemImage: "slider.vertical.3")
            }
          }
        #endif
      }
    case .quickMix, .none:
      EmptyView()
    }
  }

  /// Edit any sound, delete custom ones, with the same menu and swipe as preset rows.
  @ViewBuilder
  private func singleRow(_ sound: Sound) -> some View {
    let row = SingleSoundPickerRow(
      sound: sound, isEditMode: isEditMode, dismissOnSelect: dismissOnSelect,
      presentation: presentation, onSelection: onSelect)
    #if os(macOS)
      row.contextMenu {
        Button("Edit Sound…") { soundToEdit = sound }
        if sound.isCustom {
          Button("Delete Sound…", role: .destructive) { soundToDelete = sound }
        }
      }
    #else
      row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
        if sound.isCustom {
          Button(role: .destructive) {
            soundToDelete = sound
          } label: {
            Label("Delete", systemImage: "trash")
          }
          // Clears the inherited accent so the destructive red shows.
          .tint(nil)
        }
        Button {
          soundToEdit = sound
        } label: {
          Label("Edit", systemImage: "slider.vertical.3")
        }
      }
    #endif
  }

  private var quickMixRow: some View {
    let accent = globalSettings.customAccentColor ?? .accentColor
    return Button {
      Task { @MainActor in
        if audioManager.singleSound != nil {
          audioManager.exitSingleSoundWithoutResuming()
        }
        if !audioManager.isQuickMix {
          audioManager.enterQuickMix()
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
        NavigationStack { libraryList }
      case .sidebar:
        libraryList
      case .page:
        libraryList
          .scrollContentBackground(.hidden)
          .background { pageBackground }
          .contentMargins(.bottom, bottomBarHeight + 8, for: .scrollContent)
          #if os(iOS) || os(visionOS)
            .toolbarColorScheme(.dark, for: .navigationBar)
          #endif
      case .menuBar:
        // Matches the main window's sidebar, on the popover's own material.
        libraryList
          .scrollContentBackground(.hidden)
          .listStyle(.sidebar)
      }
    }
    // Set locally: a presented sheet doesn't reliably keep its inherited tint
    // across re-renders, and `.accentColor` rows would fall back to system blue.
    .tint(globalSettings.customAccentColor ?? .accentColor)
  }

  private var presetsExpandedBinding: Binding<Bool> {
    Binding(
      get: { globalSettings.libraryPresetsExpanded },
      set: { globalSettings.setLibraryPresetsExpanded($0) }
    )
  }

  private var soundsExpandedBinding: Binding<Bool> {
    Binding(
      get: { globalSettings.librarySoundsExpanded },
      set: { globalSettings.setLibrarySoundsExpanded($0) }
    )
  }

  @ViewBuilder
  private var libraryList: some View {
    List {
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
        Section {
          if favoriteTokens.isEmpty {
            Text(
              "Tap the star on any preset or sound to add it here."
            )
            .font(.subheadline)
            // .secondary falls just short of the contrast audit on the sidebar.
            .foregroundStyle(.primary.opacity(0.75))
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

        // Quick Mix and All Blankie Sounds are fixed. Only custom presets reorder.
        Section(isExpanded: presetsExpandedBinding) {
          // Quick Mix can't be a favorite.
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

        // Alphabetical and not reorderable. Only custom sounds can be deleted.
        Section(isExpanded: soundsExpandedBinding) {
          ForEach(singleSounds, id: \.id) { sound in
            singleRow(sound)
              .deleteDisabled(!sound.isCustom)
          }
          .onDelete(perform: deleteSounds)
        } header: {
          Text("Sounds")
        }
      }
    }
    // The sidebar leaves its bar to the controls.
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
        if presentation == .sheet {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            // Monochrome, like the system sidebar toggle (which ignores tint).
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
        // Leading on iPhone and iPad: the sidebar's trailing edge holds the
        // system sidebar toggle.
        if let onOpenSettings {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              onOpenSettings()
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
            .tint(Color.primary)
            // Marks an unopened What's New. A text badge draws as a dot, not a count.
            .badge(hasUnseenWhatsNew ? Text(verbatim: "") : nil)
            // A bar button drops accessibility values, so VoiceOver hears "New" in the label.
            .accessibilityLabel(hasUnseenWhatsNew ? Text("Settings, New") : Text("Settings"))
          }
        }
      }
    #endif
    #if os(macOS)
      // Add only: reorder works by drag, and Settings is the sidebar's footer gear.
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
    // The page is always dark over its backdrop. Applied inside the sheet and
    // alert modifiers so presented sheets keep the system appearance.
    .environment(\.colorScheme, presentation == .page ? .dark : systemColorScheme)
    .sheet(isPresented: $showingNewPresetSheet) {
      CreatePresetSheet(
        isPresented: $showingNewPresetSheet,
        onCreated: { onSelection?() }
      )
    }
    .fileImporter(
      isPresented: $showingSoundFilePicker,
      allowedContentTypes: [.audio, .blankiePreset],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      // .blankie files import as presets. Audio opens the add-sound sheet.
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
    .sheet(item: $selectedPresetForEdit) { preset in
      EditPresetSheet(preset: preset, isPresented: $selectedPresetForEdit)
    }
    .sheet(item: $soundToEdit) { sound in
      SoundSheet(mode: .edit(sound))
    }
    .alert(
      "Delete Sound",
      isPresented: .init(
        get: { soundToDelete != nil },
        set: { if !$0 { soundToDelete = nil } }
      )
    ) {
      Button("Cancel", role: .cancel) { soundToDelete = nil }
      Button("Delete", role: .destructive) {
        if let sound = soundToDelete { deleteCustomSound(sound) }
        soundToDelete = nil
      }
    } message: {
      if let sound = soundToDelete {
        Text(
          "Are you sure you want to delete '\(sound.title)'? This action cannot be undone."
        )
      }
    }
    .alert(
      "Delete Preset",
      isPresented: .init(
        get: { presetToDelete != nil },
        set: { if !$0 { presetToDelete = nil } }
      ),
      presenting: presetToDelete
    ) { preset in
      let orphanCount = presetManager.orphanedCustomSounds(ifDeleting: preset).count
      if orphanCount == 0 {
        Button("Delete", role: .destructive) {
          presetManager.deletePreset(preset)
          presetToDelete = nil
        }
      } else {
        Button(
          orphanCount == 1
            ? String(localized: "Delete Preset & 1 Sound")
            : String(localized: "Delete Preset & \(orphanCount) Sounds"),
          role: .destructive
        ) {
          presetManager.deletePreset(preset, alsoDeleteOrphanedSounds: true)
          presetToDelete = nil
        }
        Button("Delete Preset Only", role: .destructive) {
          presetManager.deletePreset(preset)
          presetToDelete = nil
        }
      }
      Button("Cancel", role: .cancel) { presetToDelete = nil }
    } message: { preset in
      let count = presetManager.orphanedCustomSounds(ifDeleting: preset).count
      if count == 0 {
        Text("Are you sure you want to delete '\(preset.name)'? This action cannot be undone.")
      } else if count == 1 {
        Text("1 custom sound is used only by '\(preset.name)'. Delete it too?")
      } else {
        Text("\(count) custom sounds are used only by '\(preset.name)'. Delete them too?")
      }
    }
  }
}

/// Leading artwork tile for picker rows. Without saved artwork it shows the
/// fallback glyph. Presets use a squircle and sounds use a circle.
struct PresetThumbnail: View {
  let artworkId: UUID?
  let preset: Preset?
  let fallbackSystemImage: String
  let tint: Color
  var isCircular = false
  /// Without saved artwork, a montage of these sound icons replaces the fallback.
  var compositeIcons: [String]? = nil
  /// All Blankie Sounds always shows the Blankie mark.
  var useBrand = false

  @Environment(\.displayScale) private var displayScale
  @State private var image: PlatformImage?

  private let size: CGFloat = 32
  private var shape: AnyShape {
    isCircular
      ? AnyShape(Circle())
      : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var glyphForFallback: FallbackArtwork.Glyph {
    if useBrand { return .brand }
    if let compositeIcons, !compositeIcons.isEmpty { return .composite(compositeIcons) }
    return .symbol(fallbackSystemImage)
  }

  var body: some View {
    Group {
      if let image {
        platformImage(image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        FallbackArtwork(
          glyph: glyphForFallback,
          accent: tint,
          size: size,
          cornerRadius: 8,
          isCircular: isCircular,
          glyphFraction: useBrand ? 0.5 : 0.44
        )
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
        // No static artwork: use the animated artwork's preview image.
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

struct LibraryView_Previews: PreviewProvider {
  static var previews: some View {
    LibraryView()
  }
}
