import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var globalSettings = GlobalSettings.shared
  #if os(iOS) || os(visionOS)
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var presetManager = PresetManager.shared
  #endif
  @State private var showingAbout = false
  @State private var showingOnboarding = false
  // Populated asynchronously from `Bundle.main.isTestFlightOrDebug` (StoreKit
  // AppTransaction). Starts `false` so App Store users never flash beta UI.
  @State private var showBetaTesterUI = false

  // Compact badge marking a Theme Default the active preset overrides, used in
  // place of a full explanatory caption.
  private var overriddenByPresetBadge: some View {
    Text("Overridden by Preset")
      .font(.caption2.weight(.semibold))
      .textCase(.uppercase)
      .foregroundColor(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(Color.secondary.opacity(0.15)))
  }

  #if os(iOS) || os(visionOS)
    // A preset can override these app-wide defaults (`nil` = follow global).
    // `themingPreset` is nil under Quick Mix (tile-only, no preset) and solo
    // mode (preserves its preset for restore but uses the app accent), so
    // neither shows these controls as overridden.
    private var presetViewModeOverride: PresetViewMode? {
      presetManager.themingPreset?.viewMode
    }
    private var accentColorOverridden: Bool {
      presetManager.themingPreset?.accentColorName != nil
    }
    private var blurOverridden: Bool {
      presetManager.themingPreset?.backgroundBlurRadius != nil
    }
  #endif

  var body: some View {
    NavigationStack {
      Form {
        if showBetaTesterUI {
          Section(
            header: Text(
              "Thanks for Testing Blankie!")
          ) {
            Link(destination: URL(string: "https://forms.gle/3K748v8G8KDrdV7E7")!) {
              HStack {
                Image(systemName: "sparkles")
                  .foregroundColor(.accentColor)
                Text(
                  "Add Your Name to the Beta Tester Credits"
                )
                .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .handCursor()
          }
        }

        PlaybackSettingsSection(globalSettings: globalSettings)

        // Always-active visual settings: applied globally, with no per-preset
        // override.
        Section(
          header: Text("Display")
        ) {
          Picker(
            selection: Binding(
              get: { globalSettings.appearance },
              set: { globalSettings.setAppearance($0) }
            )
          ) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
              Text(mode.localizedName).tag(mode)
            }
          } label: {
            Text("Appearance")
          }

          Toggle(
            isOn: Binding(
              get: { globalSettings.showSoundNames },
              set: { globalSettings.setShowSoundNames($0) }
            )
          ) {
            Text("Show Sound Names")
          }

          Toggle(
            isOn: Binding(
              get: { globalSettings.showProgressBorder },
              set: { globalSettings.setShowProgressBorder($0) }
            )
          ) {
            Text(
              "Show Progress Borders")
          }

          // Animated preset artwork as the Lock Screen / Now Playing background.
          Toggle(
            isOn: Binding(
              get: { globalSettings.lockScreenBackgroundEnabled },
              set: { globalSettings.setLockScreenBackgroundEnabled($0) }
            )
          ) {
            Text("Lock Screen Animations")
          }

        }

        // App-wide defaults a preset inherits and can override in Edit Preset
        // (view mode, accent color, background blur).
        Section(
          header: VStack(alignment: .leading, spacing: 4) {
            Text("Theme Defaults")
            Text("Presets can override these options.")
              .font(.caption)
              .textCase(.none)
          }
        ) {
          #if os(iOS) || os(visionOS)
            // View mode (Grid / List). This is the app-wide default. It's
            // locked to Grid while in Quick Mix (tile-only by design), and
            // locked while the active preset carries its own view-mode
            // override — otherwise the control would show/edit a value that
            // doesn't match what's on screen (the override wins).
            let presetOverride = presetViewModeOverride
            let pickerLocked = audioManager.isQuickMix || presetOverride != nil

            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 6) {
                Text("View Mode")
                if presetOverride != nil {
                  overriddenByPresetBadge
                }
              }
              Picker(
                selection: Binding(
                  get: {
                    if audioManager.isQuickMix { return false }
                    if let presetOverride { return presetOverride == .list }
                    return globalSettings.showingListView
                  },
                  set: { globalSettings.setShowingListView($0) }
                )
              ) {
                Text("Grid").tag(false)
                Text("List").tag(true)
              } label: {
                Text("View Mode")
              }
              .pickerStyle(.segmented)
              .disabled(pickerLocked)
            }
            .padding(.vertical, 4)
          #endif

          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              Text("Accent Color")
              #if os(iOS) || os(visionOS)
                if accentColorOverridden {
                  overriddenByPresetBadge
                }
              #endif
            }
            SpectrumColorPicker(
              selectedColor: Binding(
                get: { globalSettings.customAccentColor },
                // Use the setter so the choice persists (assigning the
                // @Published directly never writes to UserDefaults).
                set: { globalSettings.setAccentColor($0) }
              )
            )
            #if os(iOS) || os(visionOS)
              .disabled(accentColorOverridden)
            #endif
          }
          .padding(.vertical, 4)

          #if os(iOS) || os(visionOS)
            // App-wide default blur for preset background artwork. Persist only
            // on drag-end (onEditingChanged) to avoid writing UserDefaults on
            // every drag frame; the binding's setter updates the published value
            // live so the slider stays responsive.
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 6) {
                Text("Background Artwork Blur")
                if blurOverridden {
                  overriddenByPresetBadge
                }
              }
              Picker(
                "Background Artwork Blur",
                selection: Binding(
                  get: { globalSettings.backgroundBlurRadius },
                  set: { globalSettings.setBackgroundBlurRadius($0) }
                )
              ) {
                Text("None").tag(0.0)
                Text("Low").tag(7.5)
                Text("High").tag(15.0)
              }
              .pickerStyle(.segmented)
              .disabled(blurOverridden)
            }
            .padding(.vertical, 4)
          #endif
        }

        Section {
          Button {
            showingAbout = true
          } label: {
            HStack {
              Image("blankie.symbol")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
              Text("About Blankie")
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        #if DEBUG
          Section(
            header: Text("Debug")
          ) {
            Button {
              showingOnboarding = true
            } label: {
              HStack {
                Image(systemName: "ladybug.fill")
                  .foregroundColor(.orange)
                Text("Show Onboarding")
                Spacer()
              }
            }
          }
        #endif
      }
      .navigationTitle("Settings")
      // Presented as a sheet, this view has its own presentation context, so it
      // won't pick up the window's color scheme when appearance changes while
      // it's open. Apply it here too so dark/light flips the sheet immediately.
      .preferredColorScheme(globalSettings.appearance.colorScheme)
      .task {
        showBetaTesterUI = await Bundle.main.isTestFlightOrDebug
      }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              dismiss()
            }
          }
        }
      #endif
      .sheet(isPresented: $showingAbout) {
        AboutView()
      }
      .sheet(isPresented: $showingOnboarding) {
        PresetOnboardingSheet(isPresented: $showingOnboarding)
      }
    }
  }
}

// Playback preferences (Autoplay, Mix with Other Audio). Lives in the main iOS
// Settings list, above Sounds — not under Manage Sounds.
private struct PlaybackSettingsSection: View {
  #if os(iOS) || os(visionOS)
    @ObservedObject private var audioManager = AudioManager.shared
  #endif
  @ObservedObject var globalSettings: GlobalSettings

  var body: some View {
    Section(
      header: Text("Playback & Sounds")
    ) {
      #if os(iOS) || os(visionOS)
        Toggle(
          "Autoplay on Open",
          isOn: Binding(
            get: { globalSettings.autoPlayOnLaunch },
            set: { globalSettings.setAutoPlayOnLaunch($0) }
          )
        )
        .tint(globalSettings.customAccentColor ?? .accentColor)

        mixWithOthersSection
      #endif

      NavigationLink(destination: SoundManagementView()) {
        HStack {
          Text("Manage Sounds")
          Spacer()
        }
      }
    }
  }

  #if os(iOS) || os(visionOS)
    @ViewBuilder
    private var mixWithOthersSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(
          "Mix with Other Audio",
          isOn: Binding(
            get: { globalSettings.mixWithOthers },
            set: { globalSettings.setMixWithOthers($0) }
          )
        )
        .disabled(audioManager.isCarPlayConnected)
        .tint(globalSettings.customAccentColor ?? .accentColor)

        Text("When enabled, Blankie plays alongside other apps, but can't use media controls.")
          .font(.caption)
          .foregroundColor(.secondary)

        if audioManager.isCarPlayConnected {
          HStack {
            Image(systemName: "car.fill")
              .foregroundColor(.blue)
              .font(.caption)
            Text("This is unavailable while connected to CarPlay")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 4)
          .padding(.horizontal, 8)
          .background(Color.blue.opacity(0.1))
          .cornerRadius(6)
        }

        if globalSettings.mixWithOthers && !audioManager.isCarPlayConnected {
          mixWithOthersDetails
        }
      }
    }

    @ViewBuilder
    private var mixWithOthersDetails: some View {
      VStack(alignment: .leading, spacing: 8) {
        Divider()
          .padding(.vertical, 4)

        HStack {
          Text("Blankie Volume with Media")
            .font(.subheadline)
          Spacer()
          Text(
            globalSettings.volumeWithOtherAudio.formatted(.percent.precision(.fractionLength(0)))
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        Slider(
          value: Binding(
            get: { globalSettings.volumeWithOtherAudio },
            set: { globalSettings.setVolumeWithOtherAudio($0) }
          ),
          in: 0.0...1.0
        )
        .tint(globalSettings.customAccentColor ?? .accentColor)

        Text("Other media plays at system volume")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  #endif
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
