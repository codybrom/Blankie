import SwiftUI

#if os(iOS) || os(visionOS)
  struct SidebarContentView: View {
    @Binding var showingSettings: Bool
    @Binding var showingPresetPicker: Bool

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var showingListView = false
    @State private var showingCreatePreset = false

    private var customPresets: [Preset] {
      presetManager.presets.filter { !$0.isDefault }
    }

    private var recentPresets: [Preset] {
      Array(customPresets.prefix(5))
    }

    var body: some View {
      List {
        Section {
          // All Sounds (default preset)
          if let defaultPreset = presetManager.presets.first(where: { $0.isDefault }) {
            allSoundsRow(defaultPreset)
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }

          // Quick Mix
          quickMixRow()
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

          // Custom presets (5 most recent)
          ForEach(recentPresets) { preset in
            presetRow(preset)
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }

          // Browse all presets — opens the full picker modal so users can
          // reach presets that fall outside the recent-5 list in the sidebar.
          Button {
            showingPresetPicker = true
          } label: {
            Label {
              Text("Browse All Presets", comment: "Sidebar link to open the full presets modal")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "list.bullet")
                .foregroundColor(.secondary)
                .frame(width: 20)
            }
          }
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

          // New preset
          Button {
            showingCreatePreset = true
          } label: {
            Label {
              Text("New Preset", comment: "Sidebar button to create a new preset")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "plus")
                .foregroundColor(.secondary)
                .frame(width: 20)
            }
          }
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
          Text("Presets")
        }

        Section("Settings") {
          settingsButtons
        }
      }
      .onAppear {
        showingListView = globalSettings.showingListView
      }
      .sheet(isPresented: $showingCreatePreset) {
        CreatePresetSheet(isPresented: $showingCreatePreset)
      }
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
          Image(systemName: "music.note.list")
            .foregroundColor(.secondary)
            .frame(width: 20)

          Text("All Sounds")
            .foregroundColor(.primary)

          Spacer()

          if presetManager.currentPreset?.id == preset.id && !AudioManager.shared.isQuickMix {
            Image(systemName: "checkmark")
              .foregroundColor(.accentColor)
          }
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

          if AudioManager.shared.isQuickMix {
            Image(systemName: "checkmark")
              .foregroundColor(.accentColor)
          }
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
          // Preset icon - just use generic icon for now (async loading in sidebar is complex)
          Image(systemName: "music.note")
            .foregroundColor(.secondary)
            .frame(width: 20)

          Text(preset.name)
            .foregroundColor(.primary)

          Spacer()

          if presetManager.currentPreset?.id == preset.id && !AudioManager.shared.isQuickMix {
            Image(systemName: "checkmark")
              .foregroundColor(.accentColor)
          }
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
    private var settingsButtons: some View {
      Button(action: {
        showingSettings = true
      }) {
        Label {
          Text("Settings", comment: "Sidebar settings link")
        } icon: {
          Image(systemName: "gearshape")
        }
      }
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
  }
#endif
