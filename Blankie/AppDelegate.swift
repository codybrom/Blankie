//
//  AppDelegate.swift
//  Blankie
//
//  Created by Cody Bromley on 4/3/25.
//

import SwiftUI

#if os(macOS)
  final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
      configureWindowAppearance()
      setupNotificationObservers()
      applySavedLanguagePreference()
      clearRestartFlagIfNeeded()
      applyUITestingConfigurationIfNeeded()
    }

    private func configureWindowAppearance() {
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
      if let languageCode = UserDefaults.standard.string(forKey: "languagePreference"),
        languageCode != "system"
      {
        debugLog("🌐 AppDelegate: Applying saved language \(languageCode) at launch")
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
      }
    }

    private func clearRestartFlagIfNeeded() {
      if UserDefaults.standard.bool(forKey: "AppIsRestarting") {
        debugLog("🔄 App detected post-restart state for language change")
        UserDefaults.standard.removeObject(forKey: "AppIsRestarting")
      }
    }

    private func applyUITestingConfigurationIfNeeded() {
      guard ProcessInfo.processInfo.arguments.contains("-UITestingResetDefaults") else { return }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let window = NSApplication.shared.windows.first {
          let frame = NSRect(x: 485, y: 277, width: 950, height: 540)
          window.setFrame(frame, display: true, animate: false)
          debugLog("🪟 AppDelegate: Set window frame for UI testing to \(frame)")
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
            debugLog("🔊 Activated \(fileName) with volume \(volume)")
          }
        }

        audioManager.setPlaybackState(true, forceUpdate: true)
        debugLog("🎵 AppDelegate: Started playback for screenshot mode")
      }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
      return false  // Prevent app from quitting when last window closes
    }

    // Handle language change
    @objc private func languageDidChange(_: Notification) {
      debugLog("🌐 AppDelegate: Received language change notification")
      // The language has already been changed in UserDefaults by the Language.applyLanguage method

      // Try to refresh any localized strings throughout the app
      refreshAppLocalization()
    }

    // Handle locale change
    @objc private func localeDidChange(_: Notification) {
      debugLog("🌐 AppDelegate: Locale changed, refreshing localized content")
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
      debugLog("📱 IOSAppDelegate: didFinishLaunchingWithOptions")
      debugLog(
        "📱 IOSAppDelegate: Protected data available: \(application.isProtectedDataAvailable)")

      // Initialize core app systems synchronously for CarPlay compatibility
      // This MUST complete before CarPlay can connect
      #if CARPLAY_ENABLED && canImport(CarPlay)
        debugLog("🚗 IOSAppDelegate: Performing synchronous CarPlay initialization...")

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

        debugLog("🚗 IOSAppDelegate: Model context initialized")

        // Load sounds synchronously - this works even when device is locked
        // because we've configured file protection appropriately
        if AudioManager.shared.sounds.isEmpty {
          AudioManager.shared.loadSounds()
          debugLog(
            "🚗 IOSAppDelegate: Sounds loaded synchronously: \(AudioManager.shared.sounds.count) sounds"
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
        debugLog("🚗 IOSAppDelegate: Loading custom sounds...")
        await AudioManager.shared.loadCustomSoundsWhenReady()

        debugLog("🚗 IOSAppDelegate: Async app core initialization complete")
      }
    #endif

    func applicationDidBecomeActive(_: UIApplication) {
      #if CARPLAY_ENABLED && canImport(CarPlay)
        // Re-establish CarPlay connection if needed after app becomes active
        // This is crucial for CarPlay apps that were force quit or when device was locked
        if CarPlayInterfaceController.shared.isConnected {
          debugLog(
            "🚗 IOSAppDelegate: App became active with CarPlay connected, checking interface state..."
          )
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
