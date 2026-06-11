//
// CarPlayInterfaceController.swift
// Blankie
//
// Created by Cody Bromley on 6/7/25.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  @preconcurrency import CarPlay
  import Combine
  import Observation
  import SwiftData
  import SwiftUI

  class CarPlayInterfaceController: NSObject, ObservableObject, CPNowPlayingTemplateObserver {
    static let shared = CarPlayInterfaceController()

    @Published private(set) var isConnected = false
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private var timerActiveObservation: Task<Void, Never>?
    private var quickMixObservation: Task<Void, Never>?
    private var starredItemsObservation: Task<Void, Never>?
    private var globalPlayingObservation: Task<Void, Never>?
    private var soloModeObservation: Task<Void, Never>?
    private var playbackStateObservation: Task<Void, Never>?

    // Template references for updating
    private var presetsTemplate: CPListTemplate?
    private var quickMixTemplate: CPGridTemplate?
    private var soundsTemplate: CPListTemplate?
    var currentEditTemplate: CPListTemplate?
    var currentTimerTemplate: CPListTemplate?

    // Public getter for interfaceController to allow access from methods
    var currentInterfaceController: CPInterfaceController? {
      return interfaceController
    }

    // Quick Mix sounds (persisted from GlobalSettings)
    var quickMixSoundFileNames: [String] {
      return GlobalSettings.shared.quickMixSoundFileNames
    }

    /// The car display's pixel scale, for rendering template images at the right
    /// resolution. Falls back to 2x before the interface controller connects.
    var carDisplayScale: CGFloat {
      interfaceController?.carTraitCollection.displayScale ?? 2
    }

    override private init() {
      super.init()
      observeAudioManagerChanges()
      observePresetManagerChanges()
    }

    @MainActor
    func setInterfaceController(_ controller: CPInterfaceController) {
      Logger.carPlay.debug("CarPlay: Setting interface controller...")
      interfaceController = controller
      isConnected = true

      // Observe Now Playing album-artist button taps (re-register defensively in
      // case of a reconnect on the shared template).
      CPNowPlayingTemplate.shared.remove(self)
      CPNowPlayingTemplate.shared.add(self)

      // Set the tab bar root synchronously — built-ins/presets are loaded at app
      // launch, so awaiting the slower custom-sound load here just delayed the UI.
      Logger.carPlay.debug("CarPlay: Setting up interface...")
      setupTabBarInterface()

      // Finish the heavier initialization (custom sounds) in the background, then
      // refresh templates so custom sounds and any late state appear.
      Task { @MainActor in
        Logger.carPlay.debug("CarPlay: Starting background app initialization...")
        await initializeCarPlayApp()
        updateAllTemplates()
      }

      NotificationCenter.default.post(
        name: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        userInfo: ["isConnected": true]
      )
    }

    @MainActor
    func disconnect() {
      CPNowPlayingTemplate.shared.remove(self)
      currentTimerTemplate = nil
      interfaceController = nil
      isConnected = false

      // CarPlay teardown means the car route is gone and the only route left is
      // the phone, where audio must not resume. Pause first so exitQuickMix's
      // restore loop (which plays selected sounds while isGloballyPlaying) can't
      // race the .oldDeviceUnavailable route pause onto the phone speaker.
      AudioManager.shared.setGlobalPlaybackState(false)

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
      Logger.carPlay.debug("CarPlay: Checking initialization state...")
      let isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
      Logger.carPlay.debug("CarPlay: Protected data available: \(isProtectedDataAvailable)")

      // CarPlay should work even when device is locked
      // Skip waiting for protected data - CarPlay needs to function while driving
      if !isProtectedDataAvailable {
        Logger.carPlay.debug(
          "CarPlay: Device is locked, but proceeding anyway for CarPlay functionality")
      }

      // Ensure the shared container is initialized
      if !SharedModelContainer.shared.isInitialized {
        Logger.carPlay.debug("CarPlay: Initializing shared model container...")
        SharedModelContainer.shared.initialize()
      }

      // Set up manager contexts if not already done
      if AudioManager.shared.modelContext == nil {
        Logger.carPlay.debug("CarPlay: Setting up manager contexts...")
        let context = SharedModelContainer.shared.mainContext
        AudioManager.shared.setModelContext(context)
        PresetArtworkManager.shared.setModelContext(context)
      }

      // Load all sounds
      Logger.carPlay.debug("CarPlay: Loading sounds...")
      await AudioManager.shared.loadCustomSoundsWhenReady()

      Logger.carPlay.debug("CarPlay: App initialization complete")
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
        Logger.carPlay.error("CarPlay: Failed to create one or more templates")
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
            Logger.carPlay.debug("CarPlay: Successfully set tab bar interface")
          } else {
            Logger.carPlay.error(
              "CarPlay: Failed to set tab bar interface: \(error?.localizedDescription ?? "unknown error", privacy: .public)"
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
        Logger.carPlay.debug("CarPlay: Root template is not tab bar, reinitializing interface...")

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
      // Observe global playback state (AudioManager is @Observable now).
      globalPlayingObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ AudioManager.shared.isGloballyPlaying }) {
          self?.updateAllTemplates()
        }
      }

      // Observe solo mode changes. Tracks the soloed sound's id so entering or
      // leaving solo (or switching the soloed sound) refreshes the templates.
      soloModeObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ AudioManager.shared.soloModeSound?.id }) {
          self?.updateSoundsTemplate()
          self?.updateQuickMixTemplate()
          self?.updateNowPlayingButtons()
        }
      }

      // Observe sound state changes
      NotificationCenter.default.publisher(for: .soundStateChanged)
        .sink { [weak self] _ in
          self?.updateQuickMixTemplate()
        }
        .store(in: &cancellables)

      // Mirror phone-side play/pause of individual sounds onto CarPlay's tiles.
      // The Sounds list and Quick Mix grid both render a per-sound "playing"
      // state; a CarPlay tap posts `.soundStateChanged`, but a phone-side toggle
      // (which may not flip global playback) has no such signal. Tracking each
      // sound's `playbackState` closes that phone → CarPlay direction.
      playbackStateObservation = Task { @MainActor [weak self] in
        for await _ in Observations({
          AudioManager.shared.sounds.map { $0.playbackState == .playing }
        }) {
          self?.updateSoundsTemplate()
          self?.updateQuickMixTemplate()
        }
      }

      // Refresh the Quick Mix grid when its membership or order changes on
      // the phone (editor sheet or grid reorder).
      quickMixObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ GlobalSettings.shared.quickMixSoundFileNames }) {
          self?.updateQuickMixTemplate()
        }
      }

      // Swap the Now Playing timer glyph (and refresh the picker, if open) when a
      // sleep timer starts, is canceled, or expires — from CarPlay or the phone.
      // Tracks only `isTimerActive`, so the 1 Hz remainingTime tick doesn't fire it.
      timerActiveObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ TimerManager.shared.isTimerActive }) {
          guard let self else { return }
          self.updateNowPlayingButtons()
          if let timerTemplate = self.currentTimerTemplate {
            TimerOptionsTemplate.updateTemplate(timerTemplate)
          }
        }
      }
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

      // Observe favorites changes so the CarPlay Favorites section refreshes.
      starredItemsObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ GlobalSettings.shared.starredItems }) {
          self?.updatePresetsTemplate()
        }
      }

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
      // The album line surfaces the running sleep timer ("N Minute Timer");
      // tapping it opens the timer picker to set, restart, or cancel.
      Task { @MainActor in
        showTimerOptions()
      }
    }
  }

  // MARK: - Notification Names

  extension Notification.Name {
    static let soundStateChanged = Notification.Name("soundStateChanged")
  }

#endif
