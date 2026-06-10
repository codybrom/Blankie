//
//  AppDelegate.swift
//  Blankie
//
//  Created by Cody Bromley on 4/3/25.
//

import SwiftUI
import os

#if os(macOS)
  final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
      configureWindowAppearance()
      setupNotificationObservers()
      applySavedLanguagePreference()
      clearRestartFlagIfNeeded()
      applyUITestingConfigurationIfNeeded()
      DockPresenceManager.shared.start()
    }

    private func configureWindowAppearance() {
      // Blankie is dark-mode only. Lock the whole app to the dark appearance (the macOS counterpart to the iOS Info.plist UIUserInterfaceStyle = Dark key).
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
      // The language preference lives in the shared app-group suite (AppDataMigrator
      // moves it there and removes it from standard); read it from the same place
      // GlobalSettings writes it, or this fallback is always nil post-migration.
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

        // Force playback to start for screenshots
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") {
          self.configureScreenshotMode()
        }
      }
    }

    private func configureScreenshotMode() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let audioManager = AudioManager.shared

        // Configure specific sounds for screenshots
        let soundsToActivate = [
          ("rain", 0.8),
          ("storm", 0.6),
          ("wind", 0.9),
          ("waves", 0.4),
          ("boat", 0.7),
        ]

        audioManager.sounds.forEach { $0.isSelected = false }

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

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
      return false  // Prevent app from quitting when last window closes
    }

    // Handle language change
    @objc private func languageDidChange(_: Notification) {
      Logger.app.debug("AppDelegate: Received language change notification")
      // The language has already been changed in UserDefaults by the Language.applyLanguage method

      // Try to refresh any localized strings throughout the app
      refreshAppLocalization()
    }

    // Handle locale change
    @objc private func localeDidChange(_: Notification) {
      Logger.app.debug("AppDelegate: Locale changed, refreshing localized content")
      refreshAppLocalization()
    }

    private func refreshAppLocalization() {
      // Try to refresh UI elements with new language
      DispatchQueue.main.async {
        // Force redraw of all windows
        for window in NSApplication.shared.windows {
          window.update()
          window.display()

          // Try to refresh view controllers
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

      // Initialize core app systems synchronously for CarPlay compatibility
      // This MUST complete before CarPlay can connect
      #if CARPLAY_ENABLED && canImport(CarPlay)
        Logger.app.debug("IOSAppDelegate: Performing synchronous CarPlay initialization...")

        // Bridge CarPlay connection state into AudioManager. Must start before
        // CarPlay can connect so the first connect/disconnect is observed.
        CarPlayAudioBridge.shared.start()

        // Use the shared model container (don't create a duplicate!)
        if !SharedModelContainer.shared.isInitialized {
          SharedModelContainer.shared.initialize()
        }

        // Set model contexts synchronously - both are needed for CarPlay
        AudioManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
        PresetArtworkManager.shared.setModelContext(SharedModelContainer.shared.mainContext)

        Logger.app.debug("IOSAppDelegate: Model context initialized")

        // Load sounds synchronously - this works even when device is locked
        // because we've configured file protection appropriately
        if AudioManager.shared.sounds.isEmpty {
          AudioManager.shared.loadSounds()
          Logger.app.debug(
            "IOSAppDelegate: Sounds loaded synchronously: \(AudioManager.shared.sounds.count) sounds"
          )
        }

        // Async initialization for less critical components
        Task { @MainActor in
          await initializeAppCoreAsync()
        }
      #endif

      return true
    }

    #if CARPLAY_ENABLED && canImport(CarPlay)
      @MainActor
      private func initializeAppCoreAsync() async {
        // Load custom sounds with proper SwiftData coordination
        Logger.app.debug("IOSAppDelegate: Loading custom sounds...")
        await AudioManager.shared.loadCustomSoundsWhenReady()

        Logger.app.debug("IOSAppDelegate: Async app core initialization complete")
      }

      // Vend scenes explicitly — manifest-only connection is unreliable for a
      // SwiftUI `@main` app hosting a CarPlay scene. The CarPlay role gets its
      // delegate; the window role keeps SwiftUI's "Default Configuration". Role
      // matched by raw value to avoid importing CarPlay into this file.
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
        // Re-establish CarPlay connection if needed after app becomes active
        // This is crucial for CarPlay apps that were force quit or when device was locked
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
      supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
      #if os(iOS)
        if GlobalSettings.shared.lockPortraitOrientationiOS {
          return .portrait
        } else {
          return .all
        }
      #else
        return .all
      #endif
    }
  }
#endif
