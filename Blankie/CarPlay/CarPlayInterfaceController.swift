//
// CarPlayInterfaceController.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

#if CARPLAY_ENABLED

  import CarPlay
  import Combine
  import SwiftData
  import SwiftUI

  class CarPlayInterfaceController: ObservableObject {
    static let shared = CarPlayInterfaceController()

    @Published private(set) var isConnected = false
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    // Template references for updating
    private var presetsTemplate: CPListTemplate?
    private var quickMixTemplate: CPGridTemplate?
    private var soundsTemplate: CPListTemplate?

    // Quick Mix sounds (persisted from GlobalSettings)
    var quickMixSoundFileNames: [String] {
      return GlobalSettings.shared.quickMixSoundFileNames
    }

    private init() {
      observeAudioManagerChanges()
      observePresetManagerChanges()
    }

    func setInterfaceController(_ controller: CPInterfaceController) {
      print("🚗 CarPlay: Setting interface controller...")
      interfaceController = controller
      isConnected = true

      // Initialize app and setup interface directly (no loading template)
      Task { @MainActor in
        print("🚗 CarPlay: Starting app initialization...")
        await ensureAppInitialization()
        print("🚗 CarPlay: App initialization complete, setting up interface...")
        setupTabBarInterface()
      }

      NotificationCenter.default.post(
        name: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        userInfo: ["isConnected": true]
      )
    }

    @MainActor
    func disconnect() {
      interfaceController = nil
      isConnected = false

      // Exit solo mode if active
      if AudioManager.shared.soloModeSound != nil {
        AudioManager.shared.exitSoloMode()
      }

      // Exit CarPlay Quick Mix mode if active
      if AudioManager.shared.isQuickMix {
        AudioManager.shared.exitQuickMix()
      }

      NotificationCenter.default.post(
        name: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        userInfo: ["isConnected": false]
      )
    }

    // MARK: - App Initialization

    @MainActor
    private func ensureAppInitialization() async {
      // CRITICAL: All SwiftData operations MUST happen on @MainActor
      // This prevents actor violations that cause EXC_BREAKPOINT crashes
      print("🚗 CarPlay: Checking initialization state...")
      let isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
      print("🚗 CarPlay: Protected data available: \(isProtectedDataAvailable)")

      // Wait for protected data to become available if device is locked
      if !isProtectedDataAvailable {
        print("🚗 CarPlay: Device is locked, waiting for data protection to unlock...")
        await waitForProtectedDataAvailability()
      }

      // Ensure shared model container is initialized
      // This is critical for CarPlay-only launches after force quit
      if !SharedModelContainer.shared.isInitialized {
        print("🚗 CarPlay: Initializing shared model container...")
        SharedModelContainer.shared.initialize()
      }

      // Set up manager contexts if not already done
      if AudioManager.shared.modelContext == nil {
        print("🚗 CarPlay: Setting up manager contexts...")
        AudioManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
        PresetArtworkManager.shared.setModelContext(SharedModelContainer.shared.mainContext)
        print("🚗 CarPlay: Initialized SwiftData model context")
      }

      // Load ALL sounds (built-in + custom) together to prevent race conditions
      print("🚗 CarPlay: Loading all sounds and initializing PresetManager...")
      await AudioManager.shared.loadCustomSoundsWhenReady()

      print("🚗 CarPlay: App initialization complete")
    }

    /// Wait for protected data to become available (when device unlocks)
    @MainActor
    private func waitForProtectedDataAvailability() async {
      guard !UIApplication.shared.isProtectedDataAvailable else { return }

      print("🚗 CarPlay: Waiting for device unlock...")

      return await withCheckedContinuation { continuation in
        let observer = NotificationCenter.default.addObserver(
          forName: UIApplication.protectedDataDidBecomeAvailableNotification,
          object: nil,
          queue: .main
        ) { _ in
          print("🚗 CarPlay: Protected data now available - device unlocked!")
          continuation.resume()
        }

        // Clean up observer after 30 seconds to prevent hanging
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
          NotificationCenter.default.removeObserver(observer)
          print("🚗 CarPlay: Timeout waiting for unlock, proceeding anyway...")
          continuation.resume()
        }

        // Double-check if data became available while setting up observer
        if UIApplication.shared.isProtectedDataAvailable {
          NotificationCenter.default.removeObserver(observer)
          print("🚗 CarPlay: Data became available while setting up observer")
          continuation.resume()
        }
      }
    }

    // MARK: - Interface Setup

    @MainActor
    private func setupTabBarInterface() {
      guard let interfaceController = interfaceController else { return }

      // Create all three templates
      presetsTemplate = PresetListTemplate.createTemplate()
      quickMixTemplate = QuickMixGridTemplate.createTemplate()
      soundsTemplate = SoundsListTemplate.createTemplate()

      // Create tab bar with all three tabs
      let tabBar = CPTabBarTemplate(templates: [
        presetsTemplate!,
        quickMixTemplate!,
        soundsTemplate!,
      ])

      interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    // MARK: - Template Updates

    func updatePresetsTemplate() {
      guard let presetsTemplate = presetsTemplate else { return }
      PresetListTemplate.updateTemplate(presetsTemplate)
    }

    func updateQuickMixTemplate() {
      guard let quickMixTemplate = quickMixTemplate else { return }
      QuickMixGridTemplate.updateTemplate(quickMixTemplate)
    }

    func updateSoundsTemplate() {
      guard let soundsTemplate = soundsTemplate else { return }
      Task { @MainActor in
        SoundsListTemplate.updateTemplate(soundsTemplate)
      }
    }

    func updateAllTemplates() {
      updatePresetsTemplate()
      updateQuickMixTemplate()
      updateSoundsTemplate()
    }

    // MARK: - Navigation

    func showNowPlaying() {
      interfaceController?.pushTemplate(
        CPNowPlayingTemplate.shared,
        animated: true,
        completion: nil
      )
    }

    // MARK: - Observers

    private func observeAudioManagerChanges() {
      // Observe global playback state
      AudioManager.shared.$isGloballyPlaying
        .sink { [weak self] _ in
          self?.updateAllTemplates()
        }
        .store(in: &cancellables)

      // Observe solo mode changes
      AudioManager.shared.$soloModeSound
        .sink { [weak self] _ in
          self?.updateSoundsTemplate()
          self?.updateQuickMixTemplate()
        }
        .store(in: &cancellables)

      // Observe sound state changes
      NotificationCenter.default.publisher(for: .soundStateChanged)
        .sink { [weak self] _ in
          self?.updateQuickMixTemplate()
        }
        .store(in: &cancellables)
    }

    private func observePresetManagerChanges() {
      // Observe current preset
      PresetManager.shared.$currentPreset
        .sink { [weak self] _ in
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)

      // Observe presets array changes
      PresetManager.shared.$presets
        .sink { [weak self] _ in
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)
    }

    // MARK: - Helper Methods

    private func showErrorTemplate(error: Error) {
      guard let interfaceController = interfaceController else { return }

      let errorItem = CPListItem(
        text: "Failed to Load",
        detailText: "Please restart the app and try again"
      )
      let section = CPListSection(items: [errorItem])
      let errorTemplate = CPListTemplate(title: "Error", sections: [section])

      interfaceController.setRootTemplate(errorTemplate, animated: true) { _, error in
        if let error = error {
          print("❌ CarPlay: Failed to set error template: \(error)")
        }
      }
    }
  }

  // MARK: - Notification Names

  extension Notification.Name {
    static let soundStateChanged = Notification.Name("soundStateChanged")
  }

#endif
