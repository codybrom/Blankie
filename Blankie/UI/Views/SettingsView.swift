//
//  SettingsView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

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

  private let appVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

  // Compact badge marking a Theme Default the active preset overrides, used in
  // place of a full explanatory caption.
  private var overriddenByPresetBadge: some View {
    Text("Changed by Preset")
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
    NavigationStack { settingsForm }
  }

  private var settingsForm: some View {
    Form {
      // App identity header (icon, name, developer) with the About link and
      // beta/debug rows grouped beneath it, like a standard iOS settings card.
      Section {
        HStack(spacing: 14) {
          #if os(iOS)
            if let appIcon = UIApplication.shared.currentAppIcon {
              Image(uiImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                // Match the system app-icon corner ratio (~22.4% of size).
                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                .accessibilityHidden(true)
            }
          #else
            BrandedBlankieIcon(size: 60)
          #endif
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Blankie")
              .font(.system(.title3, design: .rounded).weight(.semibold))
            // Same localized key as the About sheet's version line.
            Text("Version \(appVersion) (\(buildNumber))")
              .font(.footnote)
              .foregroundColor(.secondary)
            Link(destination: URL(string: "https://forms.gle/iMhDt41LYSjukuMW8")!) {
              Text("Have Feedback?")
            }
            .font(.subheadline)
            // Borderless keeps the Link its own tap target instead of the
            // row's hit-testing owning the tap.
            .buttonStyle(.borderless)
            .handCursor()
          }
        }
        .padding(.vertical, 4)

        Button {
          showingAbout = true
        } label: {
          Label {
            Text("About Blankie")
              .foregroundColor(.primary)
          } icon: {
            Image(systemName: "hand.wave.fill")
              .symbolRenderingMode(.hierarchical)
              .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          }
        }

        #if DEBUG
          Button {
            showingOnboarding = true
          } label: {
            Label {
              Text("Show Onboarding")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "ladybug.fill")
                .foregroundColor(.orange)
            }
          }
        #endif

        if showBetaTesterUI {
          // Celebratory call-to-action for beta testers.
          Link(destination: URL(string: "https://forms.gle/3K748v8G8KDrdV7E7")!) {
            HStack(spacing: 12) {
              Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(
                  LinearGradient(
                    colors: [
                      globalSettings.customAccentColor ?? .accentColor,
                      (globalSettings.customAccentColor ?? .accentColor).opacity(0.6),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  )
                )
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text("Thanks for Testing Blankie!")
                  .font(.subheadline.weight(.semibold))
                  .foregroundColor(.primary)
                Text("Add Your Name to the Beta Tester Credits")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
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
          Text("Theme")
          Text("Presets can override these options.")
            .font(.caption)
            .textCase(.none)
        }
      ) {
        #if os(iOS) || os(visionOS)
          // View mode (Grid / List). This is the app-wide default. It's
          // locked to Grid while in Quick Mix (tile-only by design). A preset
          // override no longer locks the control — the badge marks it, and the
          // picker still shows/edits the app-wide default like Accent and Blur.
          let presetOverride = presetViewModeOverride
          let pickerLocked = audioManager.isQuickMix

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
        }
        .padding(.vertical, 4)

        #if os(iOS) || os(visionOS)
          // App-wide default blur for preset background artwork. On/off:
          // on applies `defaultBackgroundBlurRadius`, off is no blur.
          Toggle(
            isOn: Binding(
              get: { globalSettings.backgroundBlurRadius > 0 },
              set: {
                globalSettings.setBackgroundBlurRadius($0 ? defaultBackgroundBlurRadius : 0)
              }
            )
          ) {
            HStack(spacing: 6) {
              Text("Blur Background")
              if blurOverridden {
                overriddenByPresetBadge
              }
            }
          }
        #endif
      }

    }
    .navigationTitle("Settings")
    .tint(globalSettings.customAccentColor ?? .accentColor)
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
          .tint(Color.primary)
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
              .accessibilityHidden(true)
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
          .accessibilityHidden(true)
        }

        Slider(
          value: Binding(
            get: { globalSettings.volumeWithOtherAudio },
            set: { globalSettings.setVolumeWithOtherAudio($0) }
          ),
          in: 0.0...1.0
        )
        .tint(globalSettings.customAccentColor ?? .accentColor)
        .accessibilityLabel(Text("Blankie Volume with Media"))
        .accessibilityValue(
          Text(
            globalSettings.volumeWithOtherAudio.formatted(.percent.precision(.fractionLength(0)))
          )
        )

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
