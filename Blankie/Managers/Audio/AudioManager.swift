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
    debugLog("AudioManager: CarPlay connection changed to: \(connected)")
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
    debugLog("AudioManager: Initializing - START")

    // Only load sounds and state immediately - delay media controls and observers
    debugLog("AudioManager: About to loadSounds()")
    loadSounds()
    debugLog("AudioManager: About to loadSavedState()")
    loadSavedState()

    // Delay media controls and notification setup to avoid triggering audio session
    Task { @MainActor in
      // Initialize NowPlayingManager on MainActor
      self.nowPlayingManager = NowPlayingManager()

      // Allow app to fully launch before setting up delayed components
      await Task.yield()

      debugLog("AudioManager: About to setupMediaControls() (delayed)")
      self.setupMediaControls()
      debugLog("AudioManager: About to setupNotificationObservers() (delayed)")
      self.setupNotificationObservers()

      self.isInitializing = false

      debugLog("AudioManager: About to setupSoundObservers() (after initialization)")
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
    debugLog("AudioManager: Deinit called, cleanup performed")
  }
}
