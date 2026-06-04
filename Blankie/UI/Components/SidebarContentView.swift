//
//  SidebarContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  /// iPad sidebar. Hosts the full `LibraryView` so the sidebar *is* the Library
  /// — the same view iPhone shows as a sheet. The enclosing `NavigationSplitView`
  /// puts its show/hide toggle trailing; Settings rides in the Library's leading toolbar.
  struct SidebarContentView: View {
    @Binding var showingSettings: Bool

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @StateObject private var audioManager = AudioManager.shared

    /// The sidebar follows the theming preset: its accent, then the app-wide
    /// custom accent, then the system accent. `themingPreset` is nil during
    /// solo / Quick Mix, so those use the app accent.
    private var activeAccent: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
      LibraryView(presentation: .sidebar, onOpenSettings: { showingSettings = true })
        .tint(activeAccent)
        .onAppear {
          pruneStarred()
        }
        .onChange(of: presetManager.presets) { _, _ in
          pruneStarred()
        }
    }

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
      let validSounds = Set(audioManager.sounds.map { $0.fileName })
      globalSettings.pruneStarredItems(
        validPresetIDs: validIDs, validSoundFileNames: validSounds)
    }
  }
#endif
