//
//  AppDelegate.swift
//  Blankie
//
//  Created by Cody Bromley on 4/3/25.
//

import SwiftUI
import os

/// Debounced saves only land when their timers fire, so fire them before the
/// app quits (or, on iOS, suspends and may be killed without notice).
@MainActor func flushPendingSaves() {
  GlobalSettings.shared.flushPendingVolumeSave()
  for sound in AudioManager.shared.sounds { sound.flushPendingVolumeSave() }
  SoundCustomizationManager.shared.flushPendingSave()
  // A mix edit reaches the current preset only after a 100 ms coalesce.
  PresetManager.shared.updateCurrentPresetState()
  #if os(macOS)
    WindowObserver.shared.flushPendingSave()
  #endif
}

#if os(macOS)
  final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
      configureWindowAppearance()
      setupNotificationObservers()
      applySavedLanguagePreference()
      clearRestartFlagIfNeeded()
      applyUITestingConfigurationIfNeeded()
      DockPresenceManager.shared.start()
      menuBarController = MenuBarController(modelContainer: SharedModelContainer.shared.container)
    }

    private func configureWindowAppearance() {
      // Dark-only app (the macOS counterpart to the iOS UIUserInterfaceStyle = Dark key).
      NSApp.appearance = NSAppearance(named: .darkAqua)
      DispatchQueue.main.async {
        if let window = NSApplication.shared.windows.first {
          window.hasShadow = true
          window.titlebarAppearsTransparent = false
        }
      }
    }

    private func setupNotificationObservers() {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(languageDidChange),
        name: Notification.Name("LanguageDidChange"),
        object: nil
      )

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(localeDidChange),
        name: NSLocale.currentLocaleDidChangeNotification,
        object: nil
      )
    }

    private func applySavedLanguagePreference() {
      // GlobalSettings stores the language in the app-group suite (AppDataMigrator
      // moves it out of standard), so read it there.
      if let languageCode = UserDefaults.shared.string(forKey: UserDefaultsKeys.language),
        languageCode != "system"
      {
        Logger.app.debug("AppDelegate: Applying saved language \(languageCode) at launch")
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
      }
    }

    private func clearRestartFlagIfNeeded() {
      if UserDefaults.standard.bool(forKey: "AppIsRestarting") {
        Logger.app.debug("App detected post-restart state for language change")
        UserDefaults.standard.removeObject(forKey: "AppIsRestarting")
      }
    }

    private func applyUITestingConfigurationIfNeeded() {
      guard ProcessInfo.processInfo.arguments.contains("-UITestingResetDefaults") else { return }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let window = NSApplication.shared.windows.first {
          let frame = NSRect(x: 485, y: 277, width: 950, height: 540)
          window.setFrame(frame, display: true, animate: false)
          Logger.app.debug(
            "AppDelegate: Set window frame for UI testing to \(String(describing: frame))")
        }

        if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") {
          self.configureScreenshotMode()
        }
      }
    }

    private func configureScreenshotMode() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let audioManager = AudioManager.shared

        let soundsToActivate = [
          ("rain", 0.8),
          ("storm", 0.6),
          ("wind", 0.9),
          ("waves", 0.4),
          ("boat", 0.7),
        ]

        for sound in audioManager.sounds { sound.isSelected = false }

        for (fileName, volume) in soundsToActivate {
          if let sound = audioManager.sounds.first(where: { $0.fileName == fileName }) {
            sound.isSelected = true
            sound.volume = Float(volume)
            Logger.app.debug("Activated \(fileName) with volume \(volume)")
          }
        }

        audioManager.setPlaybackState(true, forceUpdate: true)
        Logger.app.debug("AppDelegate: Started playback for screenshot mode")
      }
    }

    func applicationWillTerminate(_: Notification) {
      flushPendingSaves()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
      return false
    }

    @objc private func languageDidChange(_: Notification) {
      Logger.app.debug("AppDelegate: Received language change notification")
      // Language.applyLanguage has already written the new language to UserDefaults.
      refreshAppLocalization()
    }

    @objc private func localeDidChange(_: Notification) {
      Logger.app.debug("AppDelegate: Locale changed, refreshing localized content")
      refreshAppLocalization()
    }

    private func refreshAppLocalization() {
      DispatchQueue.main.async {
        for window in NSApplication.shared.windows {
          window.update()
          window.display()

          if let contentView = window.contentView {
            contentView.needsDisplay = true
            contentView.needsLayout = true
            contentView.layout()
            contentView.display()
          }
        }
      }
    }
  }

#elseif os(iOS) || os(visionOS)
  import UIKit

  final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      Logger.app.debug("IOSAppDelegate: didFinishLaunchingWithOptions")
      Logger.app.debug(
        "IOSAppDelegate: Protected data available: \(application.isProtectedDataAvailable)")

      // Runs synchronously so core systems are ready before CarPlay can connect.
      #if CARPLAY_ENABLED && canImport(CarPlay)
        Logger.app.debug("IOSAppDelegate: Performing synchronous CarPlay initialization...")

        // Bridge CarPlay connection state into AudioManager. Must start before
        // CarPlay can connect so the first connect/disconnect is observed.
        CarPlayAudioBridge.shared.start()

        if !SharedModelContainer.shared.isInitialized {
          SharedModelContainer.shared.initialize()
        }

        // CarPlay needs both contexts.
        AudioManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
        PresetArtworkManager.shared.setModelContext(SharedModelContainer.shared.mainContext)

        Logger.app.debug("IOSAppDelegate: Model context initialized")

        // Works while the device is locked (the files it reads have no file protection).
        if AudioManager.shared.sounds.isEmpty {
          AudioManager.shared.loadSounds()
          Logger.app.debug(
            "IOSAppDelegate: Sounds loaded synchronously: \(AudioManager.shared.sounds.count) sounds"
          )
        }

        Task { @MainActor in
          await initializeAppCoreAsync()
        }
      #endif

      // Detached so the FileManager work stays off the main thread.
      Task.detached {
        StorageMaintenance.clean()
        #if DEBUG
          // After cleanup, so the report shows what's left.
          StorageReport.log()
        #endif
      }

      // A scene-based app gets no app-delegate background callback, so observe it.
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { flushPendingSaves() }
      }

      return true
    }

    func applicationWillTerminate(_: UIApplication) {
      flushPendingSaves()
    }

    #if CARPLAY_ENABLED && canImport(CarPlay)
      @MainActor
      private func initializeAppCoreAsync() async {
        Logger.app.debug("IOSAppDelegate: Loading custom sounds...")
        await AudioManager.shared.loadCustomSoundsWhenReady()

        Logger.app.debug("IOSAppDelegate: Async app core initialization complete")
      }

      // Scenes are vended explicitly because manifest-only connection is unreliable
      // for a SwiftUI `@main` app hosting a CarPlay scene. The role is matched by raw
      // value to avoid importing CarPlay into this file.
      func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
      ) -> UISceneConfiguration {
        if connectingSceneSession.role.rawValue
          == "CPTemplateApplicationSceneSessionRoleApplication"
        {
          Logger.app.debug("IOSAppDelegate: Vending CarPlay scene configuration")
          let configuration = UISceneConfiguration(
            name: "CarPlay", sessionRole: connectingSceneSession.role)
          configuration.delegateClass = CarPlaySceneDelegate.self
          return configuration
        }
        return UISceneConfiguration(
          name: "Default Configuration", sessionRole: connectingSceneSession.role)
      }
    #endif

    func applicationDidBecomeActive(_: UIApplication) {
      #if CARPLAY_ENABLED && canImport(CarPlay)
        // Covers CarPlay sessions that connected after a force quit or while locked.
        if CarPlayInterfaceController.shared.isConnected {
          Logger.app.debug(
            "IOSAppDelegate: App became active with CarPlay connected, checking interface state...")
          Task { @MainActor in
            CarPlayInterfaceController.shared.reinitializeIfNeeded()
          }
        }
      #endif
    }

    func application(
      _: UIApplication,
      supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
      #if os(iOS)
        Self.orientationMask(
          lockPortrait: GlobalSettings.shared.lockPortraitOrientationiOS,
          horizontalSizeClass: window?.traitCollection.horizontalSizeClass ?? .compact,
          verticalSizeClass: window?.traitCollection.verticalSizeClass ?? .regular)
      #else
        return .all
      #endif
    }

    #if os(iOS)
      /// Has iOS re-read `orientationMask` for every window.
      @MainActor static func refreshSupportedOrientations() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
          for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
          }
        }
      }

      /// The portrait lock is a phone-sized preference: it pins every window that
      /// isn't regular both ways (a large iPhone sideways is regular width but
      /// compact height), so only an open iPhone Duo or an iPad always rotates.
      static func orientationMask(
        lockPortrait: Bool, horizontalSizeClass: UIUserInterfaceSizeClass,
        verticalSizeClass: UIUserInterfaceSizeClass
      ) -> UIInterfaceOrientationMask {
        let regularBothWays = horizontalSizeClass == .regular && verticalSizeClass == .regular
        return lockPortrait && !regularBothWays ? .portrait : .all
      }
    #endif
  }
#endif
