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

      // Create a loading template while we initialize
      let loadingTemplate = createLoadingTemplate()
      controller.setRootTemplate(loadingTemplate, animated: false) { _, error in
        if let error = error {
          print("❌ CarPlay: Failed to set loading template: \(error)")
        }
      }

      // Ensure app is properly initialized before setting up CarPlay interface
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
      print("🚗 CarPlay: Checking initialization state...")

      // Allow run loop cycle for app delegate initialization if needed
      // This helps prevent race conditions on real devices
      if AudioManager.shared.modelContext == nil {
        print("🚗 CarPlay: Model context not ready, yielding...")
        await Task.yield()
      }

      // Double-check that core managers are initialized
      // This is critical for CarPlay-only launches after force quit
      if AudioManager.shared.modelContext == nil {
        print("🚗 CarPlay: Creating model container...")
        let modelContainer = AppSetup.createModelContainer()
        AudioManager.shared.setModelContext(modelContainer.mainContext)
        PresetArtworkManager.shared.setModelContext(modelContainer.mainContext)
        print("🚗 CarPlay: Initialized SwiftData model context")
      }

      // Load sounds if not already loaded
      if AudioManager.shared.sounds.isEmpty {
        print("🚗 CarPlay: Loading sounds...")
        AudioManager.shared.loadSounds()

        // Allow time for sounds to actually load
        await Task.yield()

        if AudioManager.shared.sounds.isEmpty {
          print("⚠️ CarPlay: Sounds still empty after waiting!")
        } else {
          print("🚗 CarPlay: Loaded \(AudioManager.shared.sounds.count) sounds")
        }
      }

      // Initialize PresetManager if needed
      if PresetManager.shared.isLoading {
        print("🚗 CarPlay: Waiting for PresetManager...")
        await PresetManager.shared.initializePresetManager()
        print(
          "🚗 CarPlay: Initialized PresetManager with \(PresetManager.shared.presets.count) presets")
      }

      print("🚗 CarPlay: App initialization complete")
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

    private func createLoadingTemplate() -> CPListTemplate {
      let item = CPListItem(text: "Loading Blankie...", detailText: "Please wait")
      let section = CPListSection(items: [item])
      let template = CPListTemplate(title: "Blankie", sections: [section])
      return template
    }

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
