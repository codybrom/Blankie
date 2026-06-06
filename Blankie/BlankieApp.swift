//
//  BlankieApp.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFAudio
import SwiftData
import SwiftUI

@main
struct BlankieApp: App {
  let modelContainer: ModelContainer
  private let appSetup: AppSetup

  // Shared state objects
  @StateObject private var globalSettings = GlobalSettings.shared
  @Environment(\.scenePhase) private var scenePhase

  #if os(macOS)
    @State private var showingAbout = false
  #endif

  // Initialize SwiftData
  init() {
    // Reset defaults if running UI tests
    UITestingHelper.resetAllDefaults()

    // Perform all data migrations (one-time operation)
    AppDataMigrator.performAllMigrations()

    // Initialize the shared container once for the entire app process
    SharedModelContainer.shared.initialize()
    modelContainer = SharedModelContainer.shared.container
    appSetup = AppSetup(modelContainer: modelContainer)
  }

  #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var windowObserver = WindowObserver.shared
    @State private var showingShortcuts = false

    var body: some Scene {
      Window("Blankie", id: "main") {
        WindowDefaults.defaultContentView(
          showingAbout: $showingAbout,
          showingShortcuts: $showingShortcuts
        )
        .sharedAppModifiers(appSetup: appSetup, globalSettings: globalSettings)
        .onChange(of: scenePhase) { oldPhase, newPhase in
          handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
      }
      .modelContainer(modelContainer)
      .defaultPosition(.center)
      .windowResizability(.contentMinSize)
      .windowStyle(.automatic)
      .defaultSize(width: WindowDefaults.defaultWidth, height: WindowDefaults.defaultHeight)
      .windowToolbarStyle(.unified)
      .commandsReplaced {
        AppCommands(
          showingAbout: $showingAbout,
          showingShortcuts: $showingShortcuts,
          hasWindow: $windowObserver.hasVisibleWindow
        )
      }

      Settings {
        SettingsView()
      }
    }

  #elseif os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var timerManager = TimerManager.shared
    @State private var showingOnboarding = false

    var body: some Scene {
      WindowGroup {
        MixerView()
          .sharedAppModifiers(appSetup: appSetup, globalSettings: globalSettings)
          .withPresetOnboarding(showOnboarding: $showingOnboarding)
          .preferredColorScheme(
            globalSettings.appearance == .system
              ? nil : (globalSettings.appearance == .dark ? .dark : .light)
          )
          .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
            timerManager.handleScenePhaseChange()
          }
      }
      .modelContainer(modelContainer)
    }
  #endif

  // MARK: - Scene Phase Handling

  private func handleScenePhaseChange(oldPhase _: ScenePhase, newPhase: ScenePhase) {
    switch newPhase {
    case .background:
      // Save state when app goes to background
      AudioManager.shared.saveState()
      Task { @MainActor in
        PresetManager.shared.savePresets()
      }
    case .inactive:
      // Save state when app becomes inactive
      AudioManager.shared.saveState()
      Task { @MainActor in
        PresetManager.shared.savePresets()
      }
    case .active:
      // App is active, no action needed
      break
    @unknown default:
      break
    }
  }
}

#if DEBUG
  struct BlankieApp_Previews: PreviewProvider {
    static var previews: some View {
      Group {
        ForEach(["Light Mode", "Dark Mode"], id: \.self) { scheme in
          Group {
            #if os(macOS)
              WindowDefaults.defaultContentView(
                showingAbout: .constant(false),
                showingShortcuts: .constant(false)
              )
              .frame(width: 450, height: 450)
            #else
              MixerView()
            #endif
          }
          .preferredColorScheme(scheme == "Dark Mode" ? .dark : .light)
          .previewDisplayName(scheme)
        }
      }
    }
  }
#endif
