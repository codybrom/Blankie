//
//  SidebarContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

/// Sidebar hosting the full `LibraryView` so the sidebar *is* the Library. On
/// iPad it's the same view iPhone shows as a sheet, with a Settings sheet in the
/// leading toolbar; on macOS Settings lives in the native Settings scene, so the
/// sidebar passes `onOpenSettings: nil`. The enclosing `NavigationSplitView`
/// supplies the show/hide toggle.
struct SidebarContentView: View {
  #if os(iOS) || os(visionOS)
    @Binding var showingSettings: Bool
  #endif

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
    #if os(iOS) || os(visionOS)
      let onOpenSettings: (() -> Void)? = { showingSettings = true }
    #else
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
