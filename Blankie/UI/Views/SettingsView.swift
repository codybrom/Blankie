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

  var body: some View {
    NavigationStack {
      Form {
        if Bundle.main.isTestFlightOrDebug {
          Section(
            header: Text(
              "Thanks for Testing Blankie!",
              comment: "Settings section header for beta tester feedback")
          ) {
            Link(destination: URL(string: "https://forms.gle/3K748v8G8KDrdV7E7")!) {
              HStack {
                Image(systemName: "sparkles")
                  .foregroundColor(.accentColor)
                Text(
                  "Add Your Name to the Beta Tester Credits",
                  comment: "Beta tester credits form link label"
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
          header: Text("Sounds", comment: "Settings section header for sound management")
        ) {
          NavigationLink(destination: SoundManagementView()) {
            HStack {
              Text("Manage Sounds", comment: "Sound management label")
              Spacer()
            }
          }
        }

        Section(
          header: Text("Appearance", comment: "Settings section header for appearance options")
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
              Text("Grid", comment: "View mode: tile/grid").tag(false)
              Text("List", comment: "View mode: list").tag(true)
            } label: {
              Text("View Mode", comment: "View mode picker label")
            }
            .pickerStyle(.segmented)
            .disabled(pickerLocked)

            if presetOverride != nil {
              Text(
                "This preset uses its own view mode. Change it in Edit Preset.",
                comment: "Caption shown when the active preset overrides the app-wide view mode"
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
            Text("Appearance", comment: "Appearance picker label")
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
            Text("Show Labels", comment: "Toggle for showing sound labels")
          }

          Toggle(
            isOn: Binding(
              get: { globalSettings.showProgressBorder },
              set: { globalSettings.setShowProgressBorder($0) }
            )
          ) {
            Text(
              "Show Progress Borders",
              comment: "Toggle for showing progress borders around playing sounds")
          }

          #if os(iOS) || os(visionOS)
            // App-wide default blur for preset background artwork. Persist only
            // on drag-end (onEditingChanged) to avoid writing UserDefaults on
            // every drag frame; the binding's setter updates the published value
            // live so the slider stays responsive.
            VStack(alignment: .leading, spacing: 8) {
              Text("Background Blur", comment: "Label for the background artwork blur slider")
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
                  Text("Background Blur", comment: "Accessibility label for background blur slider")
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
          header: Text("Lock Screen", comment: "Settings section header for lock screen options")
        ) {
          Toggle(
            isOn: Binding(
              get: { globalSettings.lockScreenBackgroundEnabled },
              set: { globalSettings.setLockScreenBackgroundEnabled($0) }
            )
          ) {
            Text("Animated Background", comment: "Toggle for lock-screen animated artwork")
          }
        }

        Section(
          header: Text("About", comment: "Settings section header for about")
        ) {
          Button {
            showingAbout = true
          } label: {
            HStack {
              Text("About Blankie", comment: "About button label")
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        #if DEBUG
          Section(
            header: Text("Debug", comment: "Settings section header for debug options")
          ) {
            Button {
              showingOnboarding = true
            } label: {
              HStack {
                Image(systemName: "ladybug.fill")
                  .foregroundColor(.orange)
                Text("Show Onboarding", comment: "Debug button to show onboarding")
                Spacer()
              }
            }
          }
        #endif
      }
      .navigationTitle("Settings")
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
