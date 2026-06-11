//
//  SidebarContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

/// Sidebar hosting the full `LibraryView` so the sidebar *is* the Library. On
/// iPad it's the same view iPhone shows as a sheet. iPad puts a Settings gear
/// in the Library's leading toolbar (sheet binding from the split view's
/// owner); macOS uses a sidebar footer row that toggles the detail-pane
/// Settings takeover (⌘, does the same). The enclosing `NavigationSplitView`
/// supplies the show/hide toggle.
struct SidebarContentView: View {
  #if os(iOS) || os(visionOS)
    @Binding var showingSettings: Bool
  #else
    @ObservedObject private var appState = AppState.shared
  #endif

  @StateObject private var presetManager = PresetManager.shared
  @State private var globalSettings = GlobalSettings.shared
  @State private var audioManager = AudioManager.shared

  /// The sidebar follows the theming preset: its accent, then the app-wide
  /// custom accent, then the system accent. `themingPreset` is nil during
  /// solo / Quick Mix, so those use the app accent.
  private var activeAccent: Color {
    presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
  }

  var body: some View {
    #if os(iOS) || os(visionOS)
      // iPad: gear in the Library's leading toolbar.
      let onOpenSettings: (() -> Void)? = { showingSettings = true }
    #else
      // macOS: the gear lives inside the sidebar as a footer row instead.
      let onOpenSettings: (() -> Void)? = nil
    #endif
    return LibraryView(presentation: .sidebar, onOpenSettings: onOpenSettings)
      .tint(activeAccent)
      .onAppear {
        pruneStarred()
      }
      .onChange(of: presetManager.presets) { _, _ in
        pruneStarred()
      }
      #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          settingsFooter
        }
      #endif
  }

  #if os(macOS)
    /// Bottom-of-sidebar Settings row (the classic Mac spot for it). Toggles
    /// the Settings pane in the detail area rather than opening a sheet.
    private var settingsFooter: some View {
      VStack(spacing: 0) {
        Divider()
        HStack {
          Button {
            appState.showingSettingsPane.toggle()
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(appState.showingSettingsPane ? activeAccent : .secondary)
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .background(.thinMaterial)
    }
  #endif

  // Drop starred tokens whose preset no longer exists. The Library only filters
  // stale favorites out of its display; pruning persists the cleanup so the
  // other consumers of `starredItems` (CarPlay, the future widget) don't carry
  // dangling tokens.
  private func pruneStarred() {
    // Don't prune while presets are still loading — otherwise an empty/partial
    // preset list at launch would drop every favorited custom preset (and
    // persist the loss). The `.onChange(of: presetManager.presets)` re-runs
    // this once they've loaded.
    guard !presetManager.isLoading, !presetManager.presets.isEmpty else { return }
    let validIDs = Set(presetManager.presets.map { $0.id.uuidString })
    // Custom sounds may be unavailable this session (SwiftData fallback / not yet
    // loaded). Union loaded sounds with the SwiftData rows, and skip solo-pruning
    // when no rows are visible but a solo favorite references an unknown sound, so
    // a transient load failure can't irreversibly drop custom-sound favorites.
    let customRowNames = Set(CustomSoundManager.shared.getAllCustomSounds().map { $0.fileName })
    let validSounds = Set(audioManager.sounds.map { $0.fileName }).union(customRowNames)
    let soloFavoriteIsUnknown = globalSettings.starredItems.contains { token in
      guard let fileName = GlobalSettings.soloFileName(fromToken: token) else { return false }
      return !validSounds.contains(fileName)
    }
    globalSettings.pruneStarredItems(
      validPresetIDs: validIDs,
      validSoundFileNames: (customRowNames.isEmpty && soloFavoriteIsUnknown) ? nil : validSounds)
  }
}
