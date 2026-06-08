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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
      Window("Blankie", id: "main") {
        WindowDefaults.defaultContentView(
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
          showingShortcuts: $showingShortcuts,
          hasWindow: $windowObserver.hasVisibleWindow
        )
      }

      // The scene must exist — with the Window scene's commands replaced, it's
      // what contributes the standard app menu (Services/Hide/Quit; removing
      // it gutted the menu). Its window is unreachable: the Settings item is
      // replaced below to open the in-window pane instead. The replacement
      // must attach HERE — a CommandGroup on the Window scene can't replace
      // another scene's menu contribution (it duplicates the item instead).
      Settings {
        SettingsView()
      }
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            // The pane lives in the main window — reopen it if closed
            AppState.shared.showingSettingsPane = true
            openWindow(id: "main")
          }
          .keyboardShortcut(.settings)
        }
      }

      // Menu bar icon + click-through popover. `isInserted` tracks the
      // "Show in Menu Bar" setting (and dragging the item out unchecks it).
      MenuBarExtra(
        isInserted: Binding(
          get: { globalSettings.showMenuBarIcon },
          // Guard equal writes: SwiftUI writes this binding back while evaluating
          // the scene, and an unconditional setter would republish mid-update —
          // an infinite "Publishing changes from within view updates" loop.
          set: { newValue in
            guard newValue != globalSettings.showMenuBarIcon else { return }
            globalSettings.setShowMenuBarIcon(newValue)
          }
        )
      ) {
        MenuBarContent()
      } label: {
        MenuBarLabel()
      }
      .menuBarExtraStyle(.window)
      .modelContainer(modelContainer)
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
          // iOS/iPadOS lock dark via Info.plist UIUserInterfaceStyle; that key
          // doesn't exist on visionOS, so force it here for that platform.
          #if os(visionOS)
            .preferredColorScheme(.dark)
          #endif
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
