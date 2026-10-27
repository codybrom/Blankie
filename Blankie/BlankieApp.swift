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

  @State private var globalSettings = GlobalSettings.shared
  @Environment(\.scenePhase) private var scenePhase

  init() {
    UITestingHelper.resetAllDefaults()

    // Migrations run first: they set `AppSetup.storeCopyPending`, which store setup reads.
    AppDataMigrator.performAllMigrations()

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

      // With the Window scene's commands replaced, this scene supplies the standard
      // app menu (Services, Hide, Quit). Its window is never opened. The Settings item
      // is replaced here because a CommandGroup on the Window scene duplicates it.
      Settings {
        SettingsView()
      }
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            // The pane lives in the main window, so reopen it if closed.
            AppState.shared.showingSettingsPane = true
            openWindow(id: "main")
          }
          .keyboardShortcut(.settings)
        }
      }

    }

  #elseif os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    @State private var presetManager = PresetManager.shared
    @State private var timerManager = TimerManager.shared
    @State private var showingOnboarding = false

    var body: some Scene {
      WindowGroup {
        MixerView()
          .sharedAppModifiers(appSetup: appSetup, globalSettings: globalSettings)
          .withPresetOnboarding(showOnboarding: $showingOnboarding)
          // iOS/iPadOS lock dark via Info.plist UIUserInterfaceStyle. That key
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
      AudioManager.shared.saveState()
      Task { @MainActor in
        PresetManager.shared.savePresets()
      }
    case .inactive:
      AudioManager.shared.saveState()
      Task { @MainActor in
        PresetManager.shared.savePresets()
      }
    case .active:
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
