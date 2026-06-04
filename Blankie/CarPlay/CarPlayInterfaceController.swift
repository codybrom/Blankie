//
// CarPlayInterfaceController.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  @preconcurrency import CarPlay
  import Combine
  import SwiftData
  import SwiftUI

  class CarPlayInterfaceController: NSObject, ObservableObject, CPNowPlayingTemplateObserver {
    static let shared = CarPlayInterfaceController()

    @Published private(set) var isConnected = false
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    // Template references for updating
    private var presetsTemplate: CPListTemplate?
    private var quickMixTemplate: CPGridTemplate?
    private var soundsTemplate: CPListTemplate?
    var currentEditTemplate: CPListTemplate?

    // Public getter for interfaceController to allow access from methods
    var currentInterfaceController: CPInterfaceController? {
      return interfaceController
    }

    // Quick Mix sounds (persisted from GlobalSettings)
    var quickMixSoundFileNames: [String] {
      return GlobalSettings.shared.quickMixSoundFileNames
    }

    override private init() {
      super.init()
      observeAudioManagerChanges()
      observePresetManagerChanges()
    }

    @MainActor
    func setInterfaceController(_ controller: CPInterfaceController) {
      debugLog("CarPlay: Setting interface controller...")
      interfaceController = controller
      isConnected = true

      // Initialize app and setup interface
      Task { @MainActor in
        debugLog("CarPlay: Starting app initialization...")

        await initializeCarPlayApp()

        debugLog("CarPlay: Setting up interface...")
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

    /// Initialize CarPlay app
    @MainActor
    private func initializeCarPlayApp() async {
      debugLog("CarPlay: Checking initialization state...")
      let isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
      debugLog("CarPlay: Protected data available: \(isProtectedDataAvailable)")

      // CarPlay should work even when device is locked
      // Skip waiting for protected data - CarPlay needs to function while driving
      if !isProtectedDataAvailable {
        debugLog("CarPlay: Device is locked, but proceeding anyway for CarPlay functionality")
      }

      // Ensure the shared container is initialized
      if !SharedModelContainer.shared.isInitialized {
        debugLog("CarPlay: Initializing shared model container...")
        SharedModelContainer.shared.initialize()
      }

      // Set up manager contexts if not already done
      if AudioManager.shared.modelContext == nil {
        debugLog("CarPlay: Setting up manager contexts...")
        let context = SharedModelContainer.shared.mainContext
        AudioManager.shared.setModelContext(context)
        PresetArtworkManager.shared.setModelContext(context)
      }

      // Load all sounds
      debugLog("CarPlay: Loading sounds...")
      await AudioManager.shared.loadCustomSoundsWhenReady()

      debugLog("CarPlay: App initialization complete")
    }

    // MARK: - Interface Setup

    @MainActor
    private func setupTabBarInterface() {
      guard let interfaceController = interfaceController else { return }

      // Create all three templates
      presetsTemplate = PresetListTemplate.createTemplate()
      quickMixTemplate = QuickMixGridTemplate.createTemplate()
      soundsTemplate = SoundsListTemplate.createTemplate()

      // Validate that templates were created successfully
      guard let presetsTemplate = presetsTemplate,
        let quickMixTemplate = quickMixTemplate,
        let soundsTemplate = soundsTemplate
      else {
        debugLog("CarPlay: Failed to create one or more templates")
        return
      }

      // Setup Now Playing template with edit functionality
      setupNowPlayingTemplate()

      // Create tab bar with all three tabs
      let tabBar = CPTabBarTemplate(templates: [
        presetsTemplate,
        soundsTemplate,
        quickMixTemplate,
      ])

      interfaceController.setRootTemplate(
        tabBar, animated: true,
        completion: { success, error in
          if success {
            debugLog("CarPlay: Successfully set tab bar interface")
          } else {
            debugLog(
              "CarPlay: Failed to set tab bar interface: \(error?.localizedDescription ?? "unknown error")"
            )
          }
        })
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

    /// Reinitialize CarPlay interface if needed (e.g., after app becomes active)
    @MainActor
    func reinitializeIfNeeded() {
      guard isConnected, let interfaceController = interfaceController else { return }

      // Check if the current root template exists
      if interfaceController.rootTemplate is CPTabBarTemplate {
        // Just update existing templates
        updateAllTemplates()
      } else {
        debugLog("CarPlay: Root template is not tab bar, reinitializing interface...")

        Task { @MainActor in
          await initializeCarPlayApp()
          setupTabBarInterface()
        }
      }
    }

    // MARK: - Navigation

    func showNowPlaying() {
      interfaceController?.pushTemplate(
        CPNowPlayingTemplate.shared,
        animated: true,
        completion: nil
      )
    }

    /// Show edit sounds interface (accessible from sounds tab)
    @MainActor
    func showEditInterface() {
      showEditSoundsInterface()
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
          Task { @MainActor in
            self?.updateSoundsTemplate()
            self?.updateQuickMixTemplate()
            self?.updateNowPlayingButtons()
          }
        }
        .store(in: &cancellables)

      // Observe sound state changes
      NotificationCenter.default.publisher(for: .soundStateChanged)
        .sink { [weak self] _ in
          self?.updateQuickMixTemplate()
        }
        .store(in: &cancellables)

      // Refresh the Quick Mix grid when its membership or order changes on
      // the phone (editor sheet or grid reorder)
      GlobalSettings.shared.$quickMixSoundFileNames
        .sink { [weak self] _ in
          Task { @MainActor in
            self?.updateQuickMixTemplate()
          }
        }
        .store(in: &cancellables)
    }

    private func observePresetManagerChanges() {
      // Observe current preset
      PresetManager.shared.$currentPreset
        .sink { [weak self] _ in
          Task { @MainActor in
            self?.updatePresetsTemplate()
            self?.updateNowPlayingButtons()
          }
        }
        .store(in: &cancellables)

      // Observe presets array changes
      PresetManager.shared.$presets
        .sink { [weak self] _ in
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)

      // Observe favorites changes so the CarPlay Favorites section refreshes
      GlobalSettings.shared.$starredItems
        .sink { [weak self] _ in
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)

      // Refresh list artwork when a preset thumbnail is regenerated or removed
      // (the thumbnail re-cache finishes after the $presets-driven rebuild).
      NotificationCenter.default.publisher(for: .presetThumbnailUpdated)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)
    }

    // MARK: - CPNowPlayingTemplateObserver

    func nowPlayingTemplateUpNextButtonTapped(_: CPNowPlayingTemplate) {
      // Not used - we're using custom buttons instead
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_: CPNowPlayingTemplate) {
      // Not used - we're using custom buttons instead
    }
  }

  // MARK: - Notification Names

  extension Notification.Name {
    static let soundStateChanged = Notification.Name("soundStateChanged")
  }

#endif
