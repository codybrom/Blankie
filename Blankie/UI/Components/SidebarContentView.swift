import SwiftUI

#if os(iOS) || os(visionOS)
  struct SidebarContentView: View {
    @Binding var showingPresetPicker: Bool
    @Binding var showingAbout: Bool
    @Binding var hideInactiveSounds: Bool
    @Binding var showingViewSettings: Bool
    @Binding var showingSoundManagement: Bool

    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var showingListView = false

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

          // Show All button
          if customPresets.count > 5 {
            Button(action: {
              showingPresetPicker = true
            }) {
              HStack {
                Text("Show All (\(customPresets.count))")
                  .foregroundColor(.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption)
                  .foregroundColor(.accentColor)
              }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          }
        } header: {
          HStack {
            Text("Presets")
            Spacer()
            Button(action: {
              showingPresetPicker = true
            }) {
              Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
          }
        }

        Section("Settings") {
          settingsButtons
        }
      }
      .onAppear {
        showingListView = globalSettings.showingListView
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
            print("Error applying preset: \(error)")
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
            print("Error applying preset: \(error)")
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

    // Settings buttons in sidebar
    private var settingsButtons: some View {
      Group {
        Button(action: {
          showingViewSettings = true
        }) {
          Label("View Settings", systemImage: "slider.horizontal.3")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

        Button(action: {
          showingSoundManagement = true
        }) {
          Label("Sound Settings", systemImage: "waveform")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

        Button(action: {
          showingAbout = true
        }) {
          Label {
            Text("About Blankie", comment: "About menu item")
          } icon: {
            Image(systemName: "info.circle")
          }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      }
    }
  }
#endif
