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

        Section(
          header: Text("Appearance")
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
          header: Text("Lock Screen")
        ) {
          Toggle(
            isOn: Binding(
              get: { globalSettings.lockScreenBackgroundEnabled },
              set: { globalSettings.setLockScreenBackgroundEnabled($0) }
            )
          ) {
            Text("Animated Background")
          }
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

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
