//
//  AudioManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI
import os

class AudioManager: ObservableObject {
  var cancellables = Set<AnyCancellable>()
  static let shared = AudioManager()
  var onReset: (() -> Void)?

  @Published var sounds: [Sound] = []
  @Published var soundsData: [SoundData] = []  // Metadata for sounds (includes mood tags)
  @Published var defaultSoundOrder: [String] = []  // Order of sounds in default view
  @Published var isGloballyPlaying: Bool = false
  @Published var soloModeSound: Sound?
  @Published var hasSelectedSounds: Bool = false
  var soloModeOriginalVolume: Float?
  var soloModeOriginalSelection: Bool?

  // Preview Mode (separate from solo mode for SoundSheet previews)
  @Published var previewModeSound: Sound?
  var previewModeOriginalStates: [String: PreviewOriginalState] = [:]

  struct PreviewOriginalState {
    let volume: Float
    let isPlaying: Bool
  }

  // CarPlay connection state, pushed in by `CarPlayAudioBridge`. Stays `false`
  // on platforms that don't build CarPlay support. Read by
  // `setupAudioSessionForPlayback` to configure the audio session appropriately.
  @Published private(set) var isCarPlayConnected: Bool = false

  /// Called by `CarPlayAudioBridge` when CarPlay connects or disconnects.
  /// Updates `isCarPlayConnected` and, if audio is currently playing, reconfigures
  /// the audio session so it picks up the new routing policy.
  @MainActor
  func setCarPlayConnected(_ connected: Bool) {
    guard isCarPlayConnected != connected else { return }
    Logger.audio.debug("AudioManager: CarPlay connection changed to: \(connected)")
    isCarPlayConnected = connected

    #if os(iOS) || os(visionOS)
      if isGloballyPlaying {
        setupAudioSessionForPlayback()
      }
    #endif
  }

  // Quick Mix Mode
  @Published var isQuickMix: Bool = false
  struct QuickMixState {
    let sound: Sound
    let isSelected: Bool
    let volume: Float
  }

  var quickMixOriginalStates: [QuickMixState] = []
  var preQuickMixPreset: Preset?

  var modelContext: ModelContext?
  var nowPlayingManager: NowPlayingManager!
  @MainActor var isInitializing = true
  /// Set once custom sounds have been loaded from SwiftData. Guards against a
  /// second full reload — on the CarPlay build both `IOSAppDelegate` and
  /// `AppSetup` call `loadCustomSoundsWhenReady()`, and re-running the load
  /// would re-instantiate custom `Sound` objects that the UI/preset still
  /// references, orphaning the originals (which then can't be stopped).
  @MainActor var hasLoadedCustomSounds = false
  var customSoundObserver: AnyCancellable?
  #if os(iOS) || os(visionOS)
    var audioSessionObserversSetup = false
  #endif

  private init() {
    Logger.audio.debug("AudioManager: Initializing - START")

    // Only load sounds and state immediately - delay media controls and observers
    Logger.audio.debug("AudioManager: About to loadSounds()")
    loadSounds()
    Logger.audio.debug("AudioManager: About to loadSavedState()")
    loadSavedState()

    // Delay media controls and notification setup to avoid triggering audio session
    Task { @MainActor in
      // Initialize NowPlayingManager on MainActor
      self.nowPlayingManager = NowPlayingManager()

      // Allow app to fully launch before setting up delayed components
      await Task.yield()

      Logger.audio.debug("AudioManager: About to setupMediaControls() (delayed)")
      self.setupMediaControls()
      Logger.audio.debug("AudioManager: About to setupNotificationObservers() (delayed)")
      self.setupNotificationObservers()

      self.isInitializing = false

      Logger.audio.debug("AudioManager: About to setupSoundObservers() (after initialization)")
      self.setupSoundObservers()

      // Analyze custom sounds that might be missing profiles
      Task {
        await self.analyzeCustomSoundsIfNeeded()
      }

      // Restore solo mode if it was saved (respecting auto-play). A custom solo
      // sound may not be loaded yet here; restoreSoloModeIfNeeded() reports true
      // so we don't fall back to the preset prematurely, and
      // loadCustomSoundsWhenReady() finishes (or abandons) the restore once
      // custom sounds load.
      if self.restoreSoloModeIfNeeded() {
        // Solo restored (or pending a still-loading custom sound).
      } else {
        self.applyPresetLaunchState()
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    cleanup()
    Logger.audio.debug("AudioManager: Deinit called, cleanup performed")
  }
}

// MARK: - Initialization Helpers

extension AudioManager {
  func setupSoundObservers() {
    // Clear any existing observers
    cancellables.removeAll()
    // Set up new observers for each sound
    for sound in sounds {
      sound.objectWillChange
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          guard let self = self else { return }
          Task { @MainActor in
            self.updateHasSelectedSounds()
            PresetManager.shared.updateCurrentPresetState()
          }
        }
        .store(in: &cancellables)
    }

    // Update initial state
    updateHasSelectedSounds()
  }

  func updateHasSelectedSounds() {
    let newValue = sounds.contains { $0.isSelected }
    if hasSelectedSounds != newValue {
      Logger.audio.debug(
        "AudioManager: hasSelectedSounds changed from \(self.hasSelectedSounds) to \(newValue)")
      hasSelectedSounds = newValue

      // Turning off the last sound pauses playback: silence should read as
      // paused, never as a silent "playing" state.
      if !newValue && isGloballyPlaying {
        Logger.audio.debug("AudioManager: Last sound deselected - pausing playback")
        Task { @MainActor in
          setGlobalPlaybackState(false)
        }
      }

      // Auto-start playback when sounds are selected and nothing is currently playing
      // Only auto-start if autoplay is enabled and we're not during initialization
      if newValue && !isGloballyPlaying && !sounds.isEmpty && GlobalSettings.shared.autoPlayOnLaunch
      {
        Logger.audio.debug(
          "AudioManager: Auto-starting playback for selected sounds (autoplay enabled)")
        Task { @MainActor in
          setGlobalPlaybackState(true)
        }
      } else if newValue && !isGloballyPlaying && !sounds.isEmpty {
        Logger.audio.debug(
          "AudioManager: Selected sounds detected but autoplay disabled - waiting for user")
      }
    }
  }

  #if os(iOS) || os(visionOS)
    func setupAudioSessionForPlayback() {
      AudioSessionManager.shared.setupForPlayback(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isCarPlayConnected: isCarPlayConnected
      )
    }
  #endif
}

// MARK: - Persistence

extension AudioManager {
  func loadSavedState() {
    guard let state = UserDefaults.shared.array(forKey: "soundState") as? [[String: Any]] else {
      return
    }
    for savedState in state {
      guard let fileName = savedState["fileName"] as? String,
        let sound = sounds.first(where: { $0.fileName == fileName })
      else {
        continue
      }
      // Only update if values have actually changed to avoid unnecessary processing
      let savedIsSelected = savedState["isSelected"] as? Bool ?? false
      let savedVolume = savedState["volume"] as? Float ?? 1.0

      if sound.isSelected != savedIsSelected {
        sound.isSelected = savedIsSelected
      }
      if sound.volume != savedVolume {
        sound.volume = savedVolume
      }
    }
  }

  func saveState() {
    // Don't save state during Quick Mix mode - volume changes are temporary
    guard !isQuickMix else {
      Logger.audio.debug("AudioManager: Skipping state save during Quick Mix mode")
      return
    }

    let state = sounds.map { sound in
      [
        "id": sound.id.uuidString,
        "fileName": sound.fileName,
        "isSelected": sound.isSelected,
        "volume": sound.volume,
      ]
    }
    UserDefaults.shared.set(state, forKey: "soundState")
  }

  func updateDefaultSoundOrder(from source: IndexSet, to destination: Int) {
    defaultSoundOrder.move(fromOffsets: source, toOffset: destination)
    UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
    objectWillChange.send()
    Logger.audio.debug(
      "AudioManager: Updated default sound order - moved from \(source) to \(destination)")
  }
}

extension AudioManager {
  // MARK: - Sound Management

  @MainActor
  func getVisibleSounds() -> [Sound] {
    sounds
  }

  /// Move a sound to a new position
  func moveSound(from sourceIndex: Int, to destinationIndex: Int) {
    guard sourceIndex < sounds.count && destinationIndex <= sounds.count else {
      return
    }

    // Move sound in the array
    let movedSound = sounds.remove(at: sourceIndex)
    sounds.insert(movedSound, at: min(destinationIndex, sounds.count))

    objectWillChange.send()
    Logger.audio.debug(
      "AudioManager: Moved sound '\(movedSound.fileName)' from \(sourceIndex) to \(destinationIndex)"
    )
  }

  /// Move a visible sound to a new position
  @MainActor
  func moveVisibleSound(from sourceIndex: Int, to destinationIndex: Int) {
    moveSound(from: sourceIndex, to: destinationIndex)
  }

  /// Apply volume settings to all playing sounds by triggering volume updates
  func applyVolumeSettings() {
    Logger.audio.debug("AudioManager: Updating volumes for volume settings change")

    for sound in sounds where sound.isSelected {
      // Trigger volume recalculation which will include custom volume settings
      sound.updateVolume()
    }
  }
}
