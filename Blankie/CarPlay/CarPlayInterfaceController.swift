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
    private var singleSoundObservation: Task<Void, Never>?
    private var playbackStateObservation: Task<Void, Never>?
    private var currentPresetObservation: Task<Void, Never>?
    private var presetsObservation: Task<Void, Never>?

    private var homeTemplate: CPListTemplate?
    private var presetsTemplate: CPListTemplate?
    private var quickMixTemplate: CPGridTemplate?
    private var soundsTemplate: CPListTemplate?
    var currentEditTemplate: CPListTemplate?
    /// The preset the open edit stack was built for.
    var currentEditPresetID: UUID?
    var currentTimerTemplate: CPListTemplate?

    var currentInterfaceController: CPInterfaceController? {
      return interfaceController
    }

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

      // Re-register on the shared template in case this is a reconnect.
      CPNowPlayingTemplate.shared.remove(self)
      CPNowPlayingTemplate.shared.add(self)

      // Set the root synchronously. Built-ins and presets load at app launch, so
      // custom sounds can finish afterward.
      Logger.carPlay.debug("CarPlay: Setting up interface...")
      setupTabBarInterface()

      // Load custom sounds in the background, then refresh the templates.
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

      // Drop the templates so the observers stop rebuilding them on the phone.
      homeTemplate = nil
      presetsTemplate = nil
      quickMixTemplate = nil
      soundsTemplate = nil
      currentEditTemplate = nil
      currentEditPresetID = nil

      // After teardown the only route left is the phone, where audio must not
      // resume. Pause first so exitQuickMix's restore loop can't start sounds there.
      AudioManager.shared.setGlobalPlaybackState(false)

      if AudioManager.shared.singleSound != nil {
        AudioManager.shared.exitSingleSound()
      }

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

    /// Prepares the store and sounds. Runs even while the device is locked.
    @MainActor
    private func initializeCarPlayApp() async {
      Logger.carPlay.debug("CarPlay: Checking initialization state...")
      let isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
      Logger.carPlay.debug("CarPlay: Protected data available: \(isProtectedDataAvailable)")

      if !isProtectedDataAvailable {
        Logger.carPlay.debug(
          "CarPlay: Device is locked, but proceeding anyway for CarPlay functionality")
      }

      if !SharedModelContainer.shared.isInitialized {
        Logger.carPlay.debug("CarPlay: Initializing shared model container...")
        SharedModelContainer.shared.initialize()
      }

      if AudioManager.shared.modelContext == nil {
        Logger.carPlay.debug("CarPlay: Setting up manager contexts...")
        let context = SharedModelContainer.shared.mainContext
        AudioManager.shared.setModelContext(context)
        PresetArtworkManager.shared.setModelContext(context)
      }

      Logger.carPlay.debug("CarPlay: Loading sounds...")
      await AudioManager.shared.loadCustomSoundsWhenReady()

      Logger.carPlay.debug("CarPlay: App initialization complete")
    }

    // MARK: - Interface Setup

    @MainActor
    private func setupTabBarInterface() {
      guard let interfaceController = interfaceController else { return }

      homeTemplate = HomeListTemplate.createTemplate()
      presetsTemplate = PresetListTemplate.createTemplate()
      quickMixTemplate = QuickMixGridTemplate.createTemplate()
      soundsTemplate = SoundsListTemplate.createTemplate()

      guard let homeTemplate = homeTemplate,
        let presetsTemplate = presetsTemplate,
        let quickMixTemplate = quickMixTemplate,
        let soundsTemplate = soundsTemplate
      else {
        Logger.carPlay.error("CarPlay: Failed to create one or more templates")
        return
      }

      setupNowPlayingTemplate()

      let tabBar = CPTabBarTemplate(templates: [
        homeTemplate,
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

    func updateHomeTemplate() {
      guard let homeTemplate = homeTemplate else { return }
      Task { @MainActor in
        HomeListTemplate.updateTemplate(homeTemplate)
      }
    }

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
      updateHomeTemplate()
      updatePresetsTemplate()
      updateQuickMixTemplate()
      updateSoundsTemplate()
    }

    /// Rebuilds the CarPlay interface if needed (for example, after the app becomes active).
    @MainActor
    func reinitializeIfNeeded() {
      guard isConnected, let interfaceController = interfaceController else { return }

      if interfaceController.rootTemplate is CPTabBarTemplate {
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

    @MainActor
    func showEditInterface() {
      showEditSoundsInterface()
    }

    // MARK: - Observers

    private func observeAudioManagerChanges() {
      globalPlayingObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ AudioManager.shared.isGloballyPlaying }) {
          self?.updateAllTemplates()
        }
      }

      // Tracks the single sound's id so entering, leaving or switching single sound refreshes.
      singleSoundObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ AudioManager.shared.singleSound?.id }) {
          self?.updateHomeTemplate()
          self?.updateSoundsTemplate()
          self?.updateQuickMixTemplate()
          self?.updateNowPlayingButtons()
          self?.refreshOrDismissEditStack()
        }
      }

      NotificationCenter.default.publisher(for: .soundStateChanged)
        .sink { [weak self] _ in
          self?.updateQuickMixTemplate()
        }
        .store(in: &cancellables)

      // Mirrors phone-side changes to each sound's playback state, title, icon and
      // preset-use-only flag, which post no `.soundStateChanged` like CarPlay taps do.
      playbackStateObservation = Task { @MainActor [weak self] in
        for await _ in Observations({
          AudioManager.shared.sounds.map {
            ($0.playbackState == .playing, $0.isPresetUseOnly, $0.title, $0.systemIconName)
          }
        }) {
          self?.updateSoundsTemplate()
          self?.updateQuickMixTemplate()
        }
      }

      // Refresh the Quick Mix tab when its membership or order changes on the phone.
      quickMixObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ GlobalSettings.shared.quickMixSoundFileNames }) {
          self?.updateQuickMixTemplate()
        }
      }

      // Swap the Now Playing timer glyph and refresh an open picker when a timer
      // starts or ends. Tracks only `isTimerActive`, not the 1 Hz remainingTime tick.
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
      // Tracks the whole preset value so edits to the current preset refresh too.
      currentPresetObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ PresetManager.shared.currentPreset }) {
          self?.updateHomeTemplate()
          self?.updatePresetsTemplate()
          self?.updateNowPlayingButtons()
          self?.refreshOrDismissEditStack()
        }
      }

      presetsObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ PresetManager.shared.presets }) {
          self?.updateHomeTemplate()
          self?.updatePresetsTemplate()
        }
      }

      // Refresh the Home favorites and the Now Playing star, including phone-side changes.
      starredItemsObservation = Task { @MainActor [weak self] in
        for await _ in Observations({ GlobalSettings.shared.starredItems }) {
          self?.updateHomeTemplate()
          self?.updateNowPlayingButtons()
        }
      }

      // Thumbnail re-caching finishes after the presets-driven rebuild, so refresh again.
      NotificationCenter.default.publisher(for: .presetThumbnailUpdated)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.updateHomeTemplate()
          self?.updatePresetsTemplate()
        }
        .store(in: &cancellables)
    }

    // MARK: - CPNowPlayingTemplateObserver

    func nowPlayingTemplateUpNextButtonTapped(_: CPNowPlayingTemplate) {
      // Unused; the template uses custom buttons.
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
