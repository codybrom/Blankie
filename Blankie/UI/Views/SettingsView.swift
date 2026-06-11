//
//  SettingsView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI

// macOS renders a bare Button in a grouped Form as a bordered pill instead of
// a tappable list row (iOS's rendering); plain style + a full-width content
// shape restore the row look and keep the whole row clickable. No-ops on iOS.
extension View {
  @ViewBuilder
  fileprivate func formRowLabel() -> some View {
    #if os(macOS)
      self
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    #else
      self
    #endif
  }

  @ViewBuilder
  fileprivate func formRowButtonStyle() -> some View {
    #if os(macOS)
      self.buttonStyle(.plain)
    #else
      self
    #endif
  }
}

struct SettingsView: View {
  /// macOS: embedded in the main window's detail pane (sidebar gear) instead
  /// of its own sheet/scene — fills the pane and Done closes it via AppState.
  var isPane = false
  @Environment(\.dismiss) private var dismiss
  private let globalSettings = GlobalSettings.shared
  #if os(iOS) || os(visionOS)
    private let audioManager = AudioManager.shared
    private let presetManager = PresetManager.shared
  #endif
  @State private var showingOnboarding = false
  #if os(macOS)
    /// Holds the in-pane About sub-page flag (app-level so the menu bar's
    /// About Blankie can open straight to it; reset when the pane closes).
    @ObservedObject private var appState = AppState.shared
  #endif
  #if os(macOS)
    @State private var showingRestartAlert = false
  #endif
  // Populated asynchronously from `Bundle.main.isTestFlightOrDebug` (StoreKit
  // AppTransaction). Starts `false` so App Store users never flash beta UI.
  @State private var showBetaTesterUI = false

  private let appVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

  private var aboutRowLabel: some View {
    Label {
      Text("About Blankie")
        .foregroundColor(.primary)
    } icon: {
      Image(systemName: "hand.wave.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
    }
  }

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

  @ViewBuilder
  var body: some View {
    if isPane {
      // About swaps in-pane rather than via NavigationLink: a NavigationStack
      // push here escapes the pane and takes over the whole detail column,
      // hiding the playback bar below.
      NavigationStack {
        #if os(macOS)
          if appState.showingSettingsAboutPage {
            AboutView()
              .toolbar { paneSubPageToolbar }
          } else if appState.showingSettingsManageSoundsPage {
            SoundManagementView()
              .toolbar { paneSubPageToolbar }
          } else {
            settingsForm
          }
        #else
          settingsForm
        #endif
      }
      #if os(macOS)
        // After the pane is fully gone, reset to the root settings list so
        // the next open (gear/⌘,) starts there. Doing this on the pane flag
        // itself flashed the root mid-fade-out.
        .onDisappear {
          appState.showingSettingsAboutPage = false
          appState.showingSettingsManageSoundsPage = false
        }
      #endif
    } else {
      NavigationStack { settingsForm }
        #if os(macOS)
          // Tuned sheet/scene size; the grouped form scrolls inside it.
          .frame(width: 500, height: 640)
        #endif
    }
  }

  #if os(macOS)
    /// Back/Done toolbar shared by the pane's in-pane sub-pages (About,
    /// Manage Sounds). Done ends Settings entirely — the pane's onDisappear
    /// then resets the sub-page flags.
    @ToolbarContentBuilder
    private var paneSubPageToolbar: some ToolbarContent {
      ToolbarItem(placement: .navigation) {
        Button {
          appState.showingSettingsAboutPage = false
          appState.showingSettingsManageSoundsPage = false
        } label: {
          Label("Back", systemImage: "chevron.left")
        }
        .accessibilityLabel("Back to Settings")
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          appState.showingSettingsPane = false
        }
        .tint(Color.primary)
      }
    }
  #endif

  /// App-wide accent color row: iOS shows it in Theme (with the preset
  /// override badge), macOS in Display.
  private var accentColorControl: some View {
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
  }

  #if os(macOS)
    private var languageMenu: some View {
      Picker(
        "Language",
        selection: Binding(
          get: { globalSettings.language },
          set: { globalSettings.setLanguage($0) }
        )
      ) {
        ForEach(globalSettings.availableLanguages) { language in
          HStack {
            Image(systemName: language.icon)
            Text(language.displayName)
          }
          .tag(language)
        }
      }
      .pickerStyle(.menu)
    }

    /// App-level macOS settings: menu bar presence, Dock-icon behavior, the Dock
    /// pause badge, and language. The Dock-hiding toggles only appear when the
    /// menu bar icon is shown (so a closed window is never unreachable), and
    /// "Hide Dock Icon When Window Is Closed" hides under Menu Bar Only, which
    /// already keeps the Dock icon hidden.
    private var appSection: some View {
      Section(header: Text("App")) {
        Toggle(
          isOn: Binding(
            get: { globalSettings.showMenuBarIcon },
            set: { globalSettings.setShowMenuBarIcon($0) }
          )
        ) {
          Text("Show in Menu Bar")
        }

        if globalSettings.showMenuBarIcon {
          Toggle(
            isOn: Binding(
              get: { globalSettings.menuBarOnlyMode },
              set: { globalSettings.setMenuBarOnlyMode($0) }
            )
          ) {
            Text("Menu Bar Only")
          }

          if !globalSettings.menuBarOnlyMode {
            Toggle(
              isOn: Binding(
                get: { globalSettings.hideDockWhenWindowClosed },
                set: { globalSettings.setHideDockWhenWindowClosed($0) }
              )
            ) {
              Text("Hide Dock Icon When Window Is Closed")
            }
          }
        }

        Toggle(
          isOn: Binding(
            get: { globalSettings.showDockBadgeWhenPaused },
            set: { globalSettings.setShowDockBadgeWhenPaused($0) }
          )
        ) {
          Text("Show Dock Icon Badge When Paused")
        }

        languageMenu
      }
    }
  #endif

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

        // About is a sub-page on both platforms: iOS pushes in the settings
        // sheet's stack; macOS swaps in-pane (a push there escapes the pane).
        // (In the unreachable macOS sheet/scene this row no-ops.)
        #if os(macOS)
          Button {
            appState.showingSettingsAboutPage = true
          } label: {
            HStack {
              aboutRowLabel
              Spacer()
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .formRowLabel()
          }
          .formRowButtonStyle()
        #else
          NavigationLink {
            AboutView()
          } label: {
            aboutRowLabel
          }
        #endif

        // Help row, relocated from the About page's footer.
        Link(destination: URL(string: "https://blankie.rest/faq")!) {
          HStack {
            Label {
              Text("Blankie Help")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "questionmark.circle")
                .foregroundStyle(.tint)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
          .formRowLabel()
        }
        .formRowButtonStyle()
        .handCursor()

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
            .formRowLabel()
          }
          .formRowButtonStyle()
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

        #if os(iOS) || os(visionOS)
          // Animated preset artwork as the Lock Screen / Now Playing background.
          Toggle(
            isOn: Binding(
              get: { globalSettings.lockScreenBackgroundEnabled },
              set: { globalSettings.setLockScreenBackgroundEnabled($0) }
            )
          ) {
            Text("Lock Screen Animations")
          }
        #endif

        #if os(macOS)
          // Accent lives in Display (Theme is iOS-only). The Dock badge and
          // Language moved to the App section below.
          accentColorControl
        #endif
      }

      #if os(macOS)
        appSection
      #endif

      // App-wide defaults a preset inherits and can override in Edit Preset
      // (view mode, accent color, lock screen animation, background blur).
      // iOS-only as a section — macOS folds accent into Display above.
      #if os(iOS) || os(visionOS)
        Section {
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

          accentColorControl

          // App-wide default lock screen animation, used for any preset that
          // doesn't set its own. Hidden while Lock Screen Animations is off.
          #if os(iOS)
            if globalSettings.lockScreenBackgroundEnabled {
              AnimatedArtworkPicker(
                artwork: Binding(
                  get: { globalSettings.defaultLockScreenArtwork },
                  set: { globalSettings.setDefaultLockScreenArtwork($0) }
                ),
                staticArtworkPath: .constant(nil),
                onChange: {
                  // Republish so the lock screen reflects the new default now.
                  if let preset = presetManager.currentPreset {
                    audioManager.nowPlayingManager.forceRefresh(
                      preset: preset, isPlaying: audioManager.isGloballyPlaying)
                  }
                }
              )
            }
          #endif

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
              Text("Blur Background Images")
              if blurOverridden {
                overriddenByPresetBadge
              }
            }
          }
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Theme")
            Text("Your presets can customize these options")
              .font(.caption)
              .textCase(.none)
          }
        }
      #endif

    }
    .navigationTitle("Settings")
    #if os(macOS)
      // Grouped form so macOS renders the same inset card sections as iOS.
      .formStyle(.grouped)
    #endif
    .tint(globalSettings.customAccentColor ?? .accentColor)
    .task {
      showBetaTesterUI = await Bundle.main.isTestFlightOrDebug
    }
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            if isPane {
              AppState.shared.showingSettingsPane = false
            } else {
              dismiss()
            }
          }
          .tint(Color.primary)
        }
      }
    #endif
    #if os(macOS)
      .onChange(of: globalSettings.needsRestartForLanguageChange) { _, _ in
        if globalSettings.needsRestartForLanguageChange {
          showingRestartAlert = true
          globalSettings.needsRestartForLanguageChange = false  // reset
        }
      }
      .alert(
        Text("Language Changed"),
        isPresented: $showingRestartAlert
      ) {
        Button {
          Language.restartApp()
        } label: {
          Text("Restart Now")
        }
        Button(role: .cancel) {
        } label: {
          Text("Later")
        }
      } message: {
        Text(
          "You will need to restart Blankie for the language change to take effect."
        )
      }
    #endif
    .sheet(isPresented: $showingOnboarding) {
      PresetOnboardingSheet(isPresented: $showingOnboarding)
    }
  }
}

// Playback preferences (Autoplay, Mix with Other Audio). Lives in the main iOS
// Settings list, above Sounds — not under Manage Sounds.
private struct PlaybackSettingsSection: View {
  #if os(iOS) || os(visionOS)
    private let audioManager = AudioManager.shared
  #endif
  var globalSettings: GlobalSettings

  var body: some View {
    Section(
      header: Text("Playback & Sounds")
    ) {
      Toggle(
        "Autoplay on Open",
        isOn: Binding(
          get: { globalSettings.autoPlayOnLaunch },
          set: { globalSettings.setAutoPlayOnLaunch($0) }
        )
      )
      .tint(globalSettings.customAccentColor ?? .accentColor)

      // Mix with Other Audio is AVAudioSession-based, so it has no macOS form.
      #if os(iOS) || os(visionOS)
        mixWithOthersSection
      #endif

      spatialAvailabilitySection

      // Manage Sounds mirrors the About row: iOS pushes in the settings
      // sheet's stack; macOS swaps in-pane (a push there escapes the pane).
      // (In the unreachable macOS sheet/scene this row no-ops.)
      #if os(macOS)
        Button {
          AppState.shared.showingSettingsManageSoundsPage = true
        } label: {
          HStack {
            Text("Manage Sounds")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
          .formRowLabel()
        }
        .formRowButtonStyle()
      #else
        NavigationLink(destination: SoundManagementView()) {
          HStack {
            Text("Manage Sounds")
            Spacer()
          }
        }
      #endif
    }
  }

  /// Education-style availability gate: opting in just reveals the Spatial
  /// Mix button on presets; sessions start (and end) in the mixer itself.
  @ViewBuilder
  private var spatialAvailabilitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(
        isOn: Binding(
          get: { globalSettings.enableSpatialAudio },
          set: { globalSettings.setEnableSpatialAudio($0) }
        )
      ) {
        HStack(spacing: 6) {
          Text("Spatial Audio Mixing")
          Text("Experimental")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)

      Text(
        "Mix presets in a virtual 3D binaural space. Works best with headphones. 3D head-tracking requires compatible AirPods and Motion permission."
      )
      .font(.caption)
      .foregroundColor(.secondary)
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
