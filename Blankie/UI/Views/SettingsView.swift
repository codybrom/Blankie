//
//  SettingsView.swift
//  Blankie
//
//  Created by Cody Bromley on 4/14/25.
//

import SwiftUI

// macOS draws a bare Button in a grouped Form as a bordered pill. Plain style
// and a full-width content shape make it a clickable row, as on iOS.
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
  /// macOS: shown in the main window's detail pane. Done closes it via AppState.
  var isPane = false
  @Environment(\.dismiss) private var dismiss
  private let globalSettings = GlobalSettings.shared
  #if os(iOS) || os(visionOS)
    private let audioManager = AudioManager.shared
    private let presetManager = PresetManager.shared
  #endif
  @State private var showingOnboarding = false
  #if os(iOS)
    @State private var showingAppIconPicker = false
  #endif
  #if os(macOS)
    /// Holds the sub-page flags, app-level so About Blankie in the menu bar can
    /// open straight to About.
    @ObservedObject private var appState = AppState.shared
  #endif
  #if os(macOS)
    @State private var showingRestartAlert = false
  #endif
  // Starts false so App Store builds never flash beta UI before the async check.
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
    // `themingPreset` is nil under Quick Mix and single sound, so neither shows an override.
    private var presetViewModeOverride: PresetViewMode? {
      presetManager.themingPreset?.viewMode
    }
    private var accentColorOverridden: Bool {
      presetManager.themingPreset?.accentColorName != nil
    }
  #endif

  @ViewBuilder
  var body: some View {
    if isPane {
      // Sub-pages swap in place: a NavigationStack push here takes over the
      // whole detail column and hides the playback bar.
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
        // Reset after the pane is gone so it doesn't flash the root mid-fade.
        .onDisappear {
          appState.showingSettingsAboutPage = false
          appState.showingSettingsManageSoundsPage = false
        }
      #endif
    } else {
      NavigationStack { settingsForm }
        #if os(macOS)
          .frame(width: 500, height: 640)
        #endif
    }
  }

  #if os(macOS)
    /// Back/Done for the pane's sub-pages. Done closes Settings entirely.
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

  /// iOS shows this in Default Theme (with the override badge), macOS in Display.
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
          // The setter persists the choice.
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

    /// Dock-hiding toggles need the menu bar icon, so a closed window stays
    /// reachable. Menu Bar Only already hides the Dock icon.
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
      Section {
        HStack(spacing: 14) {
          #if os(iOS)
            if let appIcon = UIApplication.shared.currentAppIcon {
              Image(uiImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                // System app-icon corner ratio (about 22.4% of size).
                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                .accessibilityHidden(true)
            }
          #else
            BrandedBlankieIcon(size: 60)
          #endif
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Blankie")
              .font(.system(.title3, design: .rounded).weight(.semibold))
            // Shares its localized key with the About sheet.
            Text("Version \(appVersion) (\(buildNumber))")
              .font(.footnote)
              .foregroundColor(.secondary)
            Link(destination: URL(string: "https://forms.gle/iMhDt41LYSjukuMW8")!) {
              Text("Have Feedback?")
            }
            .font(.subheadline)
            // Borderless keeps the Link its own tap target inside the row.
            .buttonStyle(.borderless)
            .handCursor()
          }
        }
        .padding(.vertical, 4)

        // macOS swaps sub-pages in the pane (a push escapes it).
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

        #if os(iOS)
          // Its own sheet, so dismissing it can't tear down the settings stack.
          Button {
            showingAppIconPicker = true
          } label: {
            Label {
              Text("Change App Icon")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "app.dashed")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
            }
            .formRowLabel()
          }
          .formRowButtonStyle()
          .sheet(isPresented: $showingAppIconPicker) {
            NavigationStack {
              AppIconPickerView()
            }
            // A `.large` detent would override `.page`.
            .presentationSizing(.page)
          }
        #endif

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

        Link(destination: URL(string: "https://blankie.rest/privacy")!) {
          HStack {
            Label {
              Text("Privacy Policy")
                .foregroundColor(.primary)
            } icon: {
              Image(systemName: "hand.raised")
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

        #if os(iOS)
          VStack(alignment: .leading, spacing: 6) {
            Toggle(
              "Open to Now Playing",
              isOn: Binding(
                get: { globalSettings.nowPlayingFirst },
                set: { globalSettings.setNowPlayingFirst($0) }
              )
            )
            Text(
              "On iPhone, presets open to Now Playing instead of the mixer."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        #endif

        #if os(iOS) || os(visionOS)
          // Toggle and default picker share one row so the picker reads as a
          // sub-option. The default covers Quick Mix and All Blankie Sounds.
          VStack(alignment: .leading, spacing: 12) {
            Toggle(
              isOn: Binding(
                get: { globalSettings.lockScreenBackgroundEnabled },
                set: { globalSettings.setLockScreenBackgroundEnabled($0) }
              )
            ) {
              Text("Lock Screen Animations")
            }

            #if os(iOS)
              if globalSettings.lockScreenBackgroundEnabled {
                AnimatedArtworkPicker(
                  artwork: Binding(
                    get: { globalSettings.defaultLockScreenArtwork },
                    set: { globalSettings.setDefaultLockScreenArtwork($0) }
                  ),
                  staticArtworkPath: .constant(nil),
                  label: "Default Animation",
                  onChange: {
                    // Republish so the Lock Screen shows the new default now.
                    if let preset = presetManager.currentPreset {
                      audioManager.nowPlayingManager.forceRefresh(
                        preset: preset, isPlaying: audioManager.isGloballyPlaying)
                    }
                  }
                )
                .padding(.top, 8)
                .padding(.leading, 16)

                Text("Presets can choose their own artwork when you edit them.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .padding(.leading, 16)
              }
            #endif
          }

          // On applies `defaultBackgroundBlurRadius`, off is no blur. The Mac
          // backdrop uses the same saved radius but has no toggle.
          Toggle(
            isOn: Binding(
              get: { globalSettings.backgroundBlurRadius > 0 },
              set: {
                globalSettings.setBackgroundBlurRadius($0 ? defaultBackgroundBlurRadius : 0)
              }
            )
          ) {
            Text("Blur Background Images")
          }
        #endif

        #if os(macOS)
          // Default Theme is iOS-only, so the accent lives here on macOS.
          accentColorControl
        #endif
      }

      #if os(macOS)
        appSection
      #endif

      // App-wide defaults a preset can override in Edit Preset.
      #if os(iOS) || os(visionOS)
        Section {
          // Locked to Grid in Quick Mix. A preset override only shows the
          // badge. The picker still edits the app-wide default.
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
        } header: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Default Theme")
          }
        }
      #endif

    }
    .navigationTitle("Settings")
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .tint(globalSettings.customAccentColor ?? .accentColor)
    .task {
      showBetaTesterUI = await Bundle.main.isTestFlightOrDebug()
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

private struct PlaybackSettingsSection: View {
  #if os(iOS) || os(visionOS)
    private let audioManager = AudioManager.shared
  #endif
  var globalSettings: GlobalSettings

  var body: some View {
    Section(
      header: Text("Playback & Sounds")
    ) {
      // macOS only: iOS keeps running in the background.
      #if os(macOS)
        Toggle(
          "Autoplay on Open",
          isOn: Binding(
            get: { globalSettings.autoPlayOnLaunch },
            set: { globalSettings.setAutoPlayOnLaunch($0) }
          )
        )
        .tint(globalSettings.customAccentColor ?? .accentColor)
      #endif

      if #available(iOS 27, macOS 27, visionOS 27, *) {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(
            "Show Playback as Continuous",
            isOn: Binding(
              get: { globalSettings.showPlaybackAsContinuous },
              set: { globalSettings.setShowPlaybackAsContinuous($0) }
            )
          )
          .tint(globalSettings.customAccentColor ?? .accentColor)
          Text(
            "Hide sound and preset progress bars in Now Playing and the player. Sleep timer countdowns stay visible."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }

      // AVAudioSession only, so there's no macOS version.
      #if os(iOS) || os(visionOS)
        mixWithOthersSection
      #endif

      spatialAvailabilitySection

      // Swaps in the pane on macOS, like the About row.
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

  /// Opting in only reveals the Spatial Mix button on presets.
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

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
