//
//  SidebarContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

/// Sidebar hosting the full `LibraryView` (the view iPhone shows as a sheet). iPad
/// puts a Settings gear in the Library's leading toolbar; macOS uses a footer row
/// that toggles the Settings detail pane, as ⌘, does.
struct SidebarContentView: View {
  #if os(iOS) || os(visionOS)
    @Binding var showingSettings: Bool
  #else
    @ObservedObject private var appState = AppState.shared
  #endif

  @State private var presetManager = PresetManager.shared
  @State private var globalSettings = GlobalSettings.shared
  @State private var audioManager = AudioManager.shared

  /// The sidebar follows the theming preset: its accent, then the app-wide
  /// custom accent, then the system accent. `themingPreset` is nil during
  /// single sound / Quick Mix, so those use the app accent.
  private var activeAccent: Color {
    presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
  }

  var body: some View {
    #if os(iOS) || os(visionOS)
      // iPad: gear in the Library's leading toolbar.
      let onOpenSettings: (() -> Void)? = { showingSettings = true }
    #else
      // macOS: the gear is a sidebar footer row.
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
    /// Bottom-of-sidebar Settings row (the classic Mac spot). Toggles the Settings
    /// pane in the detail area.
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

  // Drops starred tokens whose preset no longer exists. The Library only hides stale
  // favorites; pruning persists it for other `starredItems` readers (CarPlay, widgets).
  private func pruneStarred() {
    // Skip while presets load, since a partial list would drop favorited custom presets.
    // The `.onChange(of: presetManager.presets)` re-runs this once they've loaded.
    guard !presetManager.isLoading, !presetManager.presets.isEmpty else { return }
    let validIDs = Set(presetManager.presets.map { $0.id.uuidString })
    // Custom sounds may be unavailable this session (SwiftData fallback or not loaded yet).
    // Union loaded sounds with SwiftData rows, and skip single-sound pruning when there are no rows
    // but a single sound favorite is unknown, so a transient load failure keeps those favorites.
    let customRowNames = Set(CustomSoundManager.shared.getAllCustomSounds().map { $0.fileName })
    let validSounds = Set(audioManager.sounds.map { $0.fileName }).union(customRowNames)
    let singleFavoriteIsUnknown = globalSettings.starredItems.contains { token in
      guard let fileName = GlobalSettings.singleFileName(fromToken: token) else { return false }
      return !validSounds.contains(fileName)
    }
    globalSettings.pruneStarredItems(
      validPresetIDs: validIDs,
      validSoundFileNames: (customRowNames.isEmpty && singleFavoriteIsUnknown) ? nil : validSounds)
  }
}
