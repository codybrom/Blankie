import SwiftUI
import TipKit

struct PresetPickerRow: View {
  let preset: Preset
  let isEditMode: Bool
  let onSelection: (() -> Void)?
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss

  init(preset: Preset, isEditMode: Bool, onSelection: (() -> Void)? = nil) {
    self.preset = preset
    self.isEditMode = isEditMode
    self.onSelection = onSelection
  }

  // The default preset is favorited under the shared "allSounds" token.
  private var starToken: String {
    preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
  }

  var body: some View {
    HStack {
      // Tap target: applies the preset (disabled while editing, where taps
      // belong to reorder/delete).
      HStack(spacing: 8) {
        if preset.isDefault {
          Image(systemName: "square.stack")
            .foregroundColor(.accentColor)
        }

        Text(preset.displayName)
          .foregroundColor(.primary)

        let isSoloModeActive = audioManager.soloModeSound != nil
        let isCurrentPreset = presetManager.currentPreset?.id == preset.id
        if !isSoloModeActive && isCurrentPreset {
          Image(systemName: "checkmark")
            .foregroundColor(.accentColor)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture {
        if !isEditMode { applyPreset() }
      }

      // Always-visible favorite toggle (hidden in edit mode, where the reorder
      // handle takes the trailing edge).
      if !isEditMode {
        Button {
          globalSettings.toggleStarred(starToken)
        } label: {
          Image(systemName: globalSettings.isStarred(starToken) ? "star.fill" : "star")
            .foregroundStyle(
              globalSettings.isStarred(starToken)
                ? (preset.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
                : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          globalSettings.isStarred(starToken)
            ? Text("Remove from Favorites") : Text("Add to Favorites"))
      }
    }
  }

  private func applyPreset() {
    Task {
      do {
        // Exit solo/Quick Mix first so the previous mix doesn't briefly play.
        if audioManager.soloModeSound != nil {
          audioManager.exitSoloModeWithoutResuming()
        }
        if audioManager.isQuickMix {
          audioManager.exitQuickMix()
        }
        try presetManager.applyPreset(preset)
        OnboardingManager.shared.markPresetSwitched()
        dismiss()
        onSelection?()
      } catch {
        debugLog("Error applying preset: \(error)")
      }
    }
  }
}

struct PresetPickerView: View {
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var onboardingManager = OnboardingManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @State private var showingNewPresetSheet = false
  @State private var presetToDelete: Preset?
  @State private var isEditMode = false
  @Environment(\.dismiss) private var dismiss

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

  // MARK: - Favorites / All Presets model

  /// Favorited tokens in saved order, dropping any whose preset no longer exists.
  private var favoriteTokens: [String] {
    globalSettings.starredItems.filter { token in
      switch token {
      case GlobalSettings.allSoundsToken: return presetManager.presets.contains { $0.isDefault }
      default: return presetManager.presets.contains { $0.id.uuidString == token }
      }
    }
  }

  /// Non-favorited custom presets in saved order. All Blankie Sounds and Quick
  /// Mix render as fixed rows in the All Presets section, NOT in this list — so
  /// the reorderable ForEach contains only reorderable customs.
  private var nonFavoriteCustomTokens: [String] {
    sortedCustomPresets.map(\.id.uuidString).filter { !globalSettings.isStarred($0) }
  }

  /// Show All Blankie Sounds as a fixed row in All Presets only when it isn't
  /// favorited (when favorited it appears in the Favorites section instead).
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
    let favoritedCustomIDs = favoriteTokens.filter { $0 != GlobalSettings.allSoundsToken }
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

  @ViewBuilder
  private func tokenRow(_ token: String) -> some View {
    switch token {
    case GlobalSettings.allSoundsToken:
      if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
        PresetPickerRow(preset: defaultPreset, isEditMode: isEditMode) { dismiss() }
      }
    default:
      if let preset = presetManager.presets.first(where: { $0.id.uuidString == token }) {
        PresetPickerRow(preset: preset, isEditMode: isEditMode) { dismiss() }
      }
    }
  }

  private var quickMixRow: some View {
    Button {
      Task { @MainActor in
        if audioManager.soloModeSound != nil {
          audioManager.exitSoloModeWithoutResuming()
        }
        if !audioManager.isQuickMix {
          audioManager.enterQuickMix()
          OnboardingManager.shared.markQuickMixUsed()
        }
        dismiss()
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "square.grid.2x2")
          .foregroundColor(.accentColor)
          .frame(width: 20)
        Text("Quick Mix")
          .foregroundColor(.primary)
        Spacer()
        if audioManager.isQuickMix {
          Image(systemName: "checkmark")
            .foregroundColor(.accentColor)
        }
      }
    }
  }

  @ViewBuilder
  private func soloIndicatorRow(_ soloSound: Sound) -> some View {
    HStack {
      HStack(spacing: 8) {
        Image(systemName: "headphones.circle.fill")
          .foregroundColor(.accentColor)
        Text("Solo Mode - \(soloSound.title)")
          .foregroundColor(.secondary)
      }
      Spacer()
      Image(systemName: "checkmark")
        .foregroundColor(.accentColor)
    }
    .listRowBackground(Color.secondary.opacity(0.1))
  }

  var body: some View {
    NavigationStack {
      List {
        // Show tip for creating first preset if no custom presets exist
        if !presetManager.hasCustomPresets {
          TipView(createFirstPresetTip, arrowEdge: .top) { action in
            if action.id == "create" {
              showingNewPresetSheet = true
            }
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }

        if presetManager.isLoading {
          // Loading view
          HStack {
            Spacer()
            ProgressView("Loading Presets...")
            Spacer()
          }
          .padding()
        } else if presetManager.presets.isEmpty {
          // Empty state
          HStack {
            Spacer()
            VStack(spacing: 12) {
              Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

              Text("No Custom Presets", comment: "Empty state title for presets")
                .font(.headline)

              Text(
                "Save your current sound configuration as a preset to quickly access it later.",
                comment: "Empty state description for presets"
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
          // Solo mode status (not part of the favorites list)
          if let soloSound = audioManager.soloModeSound {
            soloIndicatorRow(soloSound)
          }

          // FAVORITES — tap a row's star to add/remove; reorder via Edit.
          Section {
            if favoriteTokens.isEmpty {
              Text(
                "Tap the star on any preset to add it here.",
                comment: "Empty favorites hint"
              )
              .font(.subheadline)
              .foregroundStyle(.secondary)
            } else {
              ForEach(favoriteTokens, id: \.self) { token in
                tokenRow(token)
                  .deleteDisabled(!isDeletable(token))
              }
              .onMove(perform: reorderFavorites)
              .onDelete(perform: deleteFavorites)
            }
          } header: {
            Text("Favorites", comment: "Picker section header for favorited presets")
          }

          // ALL PRESETS — Quick Mix and All Blankie Sounds are fixed rows at the
          // top; only the custom presets below are reorderable in Edit.
          Section {
            // Quick Mix — always available, not favoritable (its own thing).
            quickMixRow

            if showsDefaultInAllPresets {
              tokenRow(GlobalSettings.allSoundsToken)
            }

            ForEach(nonFavoriteCustomTokens, id: \.self) { token in
              tokenRow(token)
            }
            .onMove(perform: reorderAllPresets)
            .onDelete(perform: deleteAllPresets)
          } header: {
            Text("All Presets", comment: "Picker section header for non-favorited presets")
          }
        }
      }
      .navigationTitle("Presets")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      #if os(iOS)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
          }
          ToolbarItem(placement: .topBarTrailing) {
            if presetManager.hasCustomPresets {
              Button {
                isEditMode.toggle()
              } label: {
                Text(isEditMode ? "Done" : "Edit", comment: "Edit mode toggle button")
              }
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            if !isEditMode {
              Button {
                showingNewPresetSheet = true
              } label: {
                Label("New Preset", systemImage: "plus")
              }
            }
          }
        }
      #endif
      #if os(iOS)
        .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
      #endif
      .sheet(isPresented: $showingNewPresetSheet) {
        CreatePresetSheet(isPresented: $showingNewPresetSheet)
      }
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
            "Are you sure you want to delete '\(preset.name)'? This action cannot be undone.",
            comment: "Delete preset confirmation message"
          )
        }
      }
    }
  }
}

// Preview Provider
struct PresetPickerView_Previews: PreviewProvider {
  static var previews: some View {
    PresetPickerView()
  }
}
