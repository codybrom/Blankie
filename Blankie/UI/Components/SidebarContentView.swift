import SwiftUI

#if os(iOS) || os(visionOS)
  struct SidebarContentView: View {
    @Binding var showingSettings: Bool
    @Binding var showingPresetPicker: Bool

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @StateObject private var audioManager = AudioManager.shared
    @State private var showingListView = false
    @State private var showingCreatePreset = false

    /// The sidebar follows the active preset's theme: its accent, then the
    /// app-wide custom accent, then the system accent.
    private var activeAccent: Color {
      presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    /// Trailing now-playing indicator: play/pause for the active item.
    @ViewBuilder
    private func rowIndicator(isCurrent: Bool) -> some View {
      if isCurrent {
        Image(systemName: audioManager.isGloballyPlaying ? "play.fill" : "pause.fill")
          .foregroundColor(activeAccent)
      }
    }

    /// Leading icon for a preset row: a star when favorited, else the given
    /// type icon (both muted to match the sidebar's leading-icon style).
    @ViewBuilder
    private func leadingIcon(typeIcon: String, isFavorite: Bool) -> some View {
      Image(systemName: isFavorite ? "star.fill" : typeIcon)
        .foregroundColor(.secondary)
        .frame(width: 20)
    }

    var body: some View {
      List {
        Section {
          if globalSettings.starredItems.isEmpty {
            // No favorites yet — show All Blankie Sounds so the sidebar isn't
            // just Quick Mix. Swipe to favorite it.
            if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
              allSoundsRow(defaultPreset)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                  Button {
                    globalSettings.toggleStarred(GlobalSettings.allSoundsToken)
                  } label: {
                    Label("Favorite", systemImage: "star")
                  }
                  .tint(.yellow)
                }
            }
          } else {
            // Favorited presets (and possibly All Blankie Sounds) in saved
            // order. Swipe to unfavorite; reorder happens in Browse All Presets
            // (the sidebar has no edit mode to drive a List `.onMove`).
            ForEach(globalSettings.starredItems, id: \.self) { token in
              starredRow(for: token)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button {
                    globalSettings.toggleStarred(token)
                  } label: {
                    Label("Unfavorite", systemImage: "star.slash")
                  }
                  .tint(.orange)
                }
            }
          }

          // Quick Mix — always available, pinned below favorites (not favoritable).
          quickMixRow()
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

          // Browse all presets — only when there are custom presets to browse.
          if presetManager.hasCustomPresets {
            Button {
              showingPresetPicker = true
            } label: {
              Text("More Presets")
                .foregroundColor(activeAccent)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }
        } header: {
          HStack {
            Text("Presets")
            Spacer()
            Button {
              showingCreatePreset = true
            } label: {
              Image(systemName: "plus")
                .imageScale(.large)
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .accessibilityLabel(
                  Text("New Preset"))
            }
            .buttonStyle(.borderless)
          }
        }

      }
      .safeAreaInset(edge: .bottom) {
        settingsFooter
      }
      .tint(activeAccent)
      .onAppear {
        showingListView = globalSettings.showingListView
        pruneStarred()
      }
      .onChange(of: presetManager.presets) { _, _ in
        pruneStarred()
      }
      .sheet(isPresented: $showingCreatePreset) {
        CreatePresetSheet(isPresented: $showingCreatePreset)
      }
    }

    // Resolve a starred token to its row. Unknown tokens (e.g. a preset that
    // was deleted before pruning runs) render nothing.
    @ViewBuilder
    private func starredRow(for token: String) -> some View {
      switch token {
      case GlobalSettings.allSoundsToken:
        if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
          allSoundsRow(defaultPreset)
        }
      default:
        if let preset = presetManager.presets.first(where: { $0.id.uuidString == token }) {
          presetRow(preset)
        }
      }
    }

    // Drop starred tokens whose preset no longer exists.
    private func pruneStarred() {
      // Don't prune while presets are still loading — otherwise an empty/partial
      // preset list at launch would drop every favorited custom preset (and
      // persist the loss). The `.onChange(of: presetManager.presets)` re-runs
      // this once they've loaded.
      guard !presetManager.isLoading, !presetManager.presets.isEmpty else { return }
      let validIDs = Set(presetManager.presets.map { $0.id.uuidString })
      globalSettings.pruneStarredItems(validPresetIDs: validIDs)
    }

    // All Sounds row
    private func allSoundsRow(_ preset: Preset) -> some View {
      Button(action: {
        Task {
          do {
            // Exit solo mode without resuming if active
            if AudioManager.shared.soloModeSound != nil {
              AudioManager.shared.exitSoloModeWithoutResuming()
            }

            // Exit Quick Mix if active
            if AudioManager.shared.isQuickMix {
              AudioManager.shared.exitQuickMix()
            }

            try presetManager.applyPreset(preset)
          } catch {
            debugLog("Error applying preset: \(error)")
          }
        }
      }) {
        HStack {
          leadingIcon(
            typeIcon: "music.note.list",
            isFavorite: globalSettings.isStarred(GlobalSettings.allSoundsToken))

          Text(preset.displayName)
            .foregroundColor(.primary)

          Spacer()

          rowIndicator(
            isCurrent: presetManager.currentPreset?.id == preset.id
              && !AudioManager.shared.isQuickMix)
        }
      }
    }

    // Quick Mix row
    private func quickMixRow() -> some View {
      Button(action: {
        // Exit solo mode if active
        if AudioManager.shared.soloModeSound != nil {
          AudioManager.shared.exitSoloModeWithoutResuming()
        }

        // Toggle Quick Mix or enter it
        if AudioManager.shared.isQuickMix {
          AudioManager.shared.exitQuickMix()
        } else {
          AudioManager.shared.enterQuickMix()
        }
      }) {
        HStack {
          Image(systemName: "square.grid.2x2.fill")
            .foregroundColor(.secondary)
            .frame(width: 20)

          Text("Quick Mix")
            .foregroundColor(.primary)

          Spacer()

          rowIndicator(isCurrent: AudioManager.shared.isQuickMix)
        }
      }
    }

    // Single preset row
    private func presetRow(_ preset: Preset) -> some View {
      Button(action: {
        Task {
          do {
            // Exit solo mode without resuming if active
            if AudioManager.shared.soloModeSound != nil {
              AudioManager.shared.exitSoloModeWithoutResuming()
            }

            // Exit Quick Mix if active
            if AudioManager.shared.isQuickMix {
              AudioManager.shared.exitQuickMix()
            }

            try presetManager.applyPreset(preset)
          } catch {
            debugLog("Error applying preset: \(error)")
          }
        }
      }) {
        HStack {
          leadingIcon(
            typeIcon: "music.note",
            isFavorite: globalSettings.isStarred(preset.id.uuidString))

          Text(preset.name)
            .foregroundColor(.primary)

          Spacer()

          rowIndicator(
            isCurrent: presetManager.currentPreset?.id == preset.id
              && !AudioManager.shared.isQuickMix)
        }
      }
      .contextMenu {
        if !preset.isDefault {
          Button(role: .destructive) {
            presetManager.deletePreset(preset)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }

    // Settings button in sidebar — opens the full SettingsView, which
    // already contains Manage Sounds, Appearance, About, etc.
    // Settings pinned at the bottom of the sidebar — no section header (a
    // "Settings" section containing a "Settings" row is redundant).
    private var settingsFooter: some View {
      VStack(spacing: 0) {
        Divider()
        Button {
          showingSettings = true
        } label: {
          Label {
            Text("Settings")
          } icon: {
            Image(systemName: "gearshape")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
      }
      .background(.bar)
    }
  }
#endif
