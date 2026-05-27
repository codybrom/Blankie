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

        #if os(iOS) || os(visionOS)
          PlaybackSettingsSection(globalSettings: globalSettings)
        #endif

        Section(
          header: Text("Sounds")
        ) {
          NavigationLink(destination: SoundManagementView()) {
            HStack {
              Text("Manage Sounds")
              Spacer()
            }
          }
        }

        // Always-active visual settings: applied globally, with no per-preset
        // override.
        Section(
          header: Text("Appearance")
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
            Text("Show Labels")
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
          header: Text("Preset Defaults")
        ) {
          #if os(iOS) || os(visionOS)
            // View mode (Grid / List). This is the app-wide default. It's
            // locked to Grid while in Quick Mix (tile-only by design), and
            // locked while the active preset carries its own view-mode
            // override — otherwise the control would show/edit a value that
            // doesn't match what's on screen (the override wins).
            let presetOverride =
              audioManager.isQuickMix ? nil : presetManager.currentPreset?.viewMode
            let pickerLocked = audioManager.isQuickMix || presetOverride != nil

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

            if presetOverride != nil {
              Text(
                "This preset uses its own view mode. Change it in Edit Preset."
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          #endif

          VStack(alignment: .leading, spacing: 8) {
            Text("Accent Color")
            SpectrumColorPicker(
              selectedColor: Binding(
                get: { globalSettings.customAccentColor },
                // Use the setter so the choice persists (assigning the
                // @Published directly never writes to UserDefaults).
                set: { globalSettings.setAccentColor($0) }
              ))
          }
          .padding(.vertical, 4)

          #if os(iOS) || os(visionOS)
            // App-wide default blur for preset background artwork. Persist only
            // on drag-end (onEditingChanged) to avoid writing UserDefaults on
            // every drag frame; the binding's setter updates the published value
            // live so the slider stays responsive.
            VStack(alignment: .leading, spacing: 8) {
              Text("Background Blur")
              Slider(
                value: Binding(
                  // Persist on each (stepped) change so VoiceOver/keyboard
                  // adjustments save too — not only on drag-end. step:5 means
                  // just a handful of writes per drag.
                  get: { globalSettings.backgroundBlurRadius },
                  set: { globalSettings.setBackgroundBlurRadius($0) }
                ),
                in: 0...20,
                step: 5,
                label: {
                  Text("Background Blur")
                },
                minimumValueLabel: {
                  // Small dot -> large dot encodes "less -> more" without text,
                  // so there's nothing to localize. The slider's accessibility
                  // label/value already convey meaning, so hide these caps.
                  Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                },
                maximumValueLabel: {
                  Image(systemName: "circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                },
                onEditingChanged: { editing in
                  if !editing {
                    globalSettings.setBackgroundBlurRadius(globalSettings.backgroundBlurRadius)
                  }
                }
              )
            }
            .padding(.vertical, 4)
          #endif
        }

        Section(
          header: Text("About")
        ) {
          Button {
            showingAbout = true
          } label: {
            HStack {
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
      .task {
        showBetaTesterUI = await Bundle.main.isTestFlightOrDebug
      }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
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
  @ObservedObject var globalSettings: GlobalSettings

  var body: some View {
    Section(
      header: Text("Playback")
    ) {
      Toggle(
        "Autoplay on Open",
        isOn: Binding(
          get: { globalSettings.autoPlayOnLaunch },
          set: { globalSettings.setAutoPlayOnLaunch($0) }
        )
      )
      .tint(globalSettings.customAccentColor ?? .accentColor)

      #if os(iOS) || os(visionOS)
        mixWithOthersSection
      #endif
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
        .tint(globalSettings.customAccentColor ?? .accentColor)

        if globalSettings.mixWithOthers {
          mixWithOthersDetails
        } else {
          Text("Blankie pauses other audio and responds to device media controls")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }

    @ViewBuilder
    private var mixWithOthersDetails: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
            .font(.caption)
          Text("Device media controls won't pause Blankie")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.orange.opacity(0.1))
        .cornerRadius(6)

        VStack(alignment: .leading, spacing: 8) {
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
    }
  #endif
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
