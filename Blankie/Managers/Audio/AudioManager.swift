//
//  AudioManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import Observation
import SwiftData
import SwiftUI
import os

@Observable
class AudioManager {
  static let shared = AudioManager()
  /// True only during `shared`'s synchronous init. Static so the music-exclusivity
  /// didSet can read it without re-entering `shared` mid-init, which traps.
  nonisolated(unsafe) static var isBootstrapping = true
  @ObservationIgnored var onReset: (() -> Void)?

  var sounds: [Sound] = []
  var soundsData: [SoundData] = []  // Metadata for sounds (includes mood tags)
  var defaultSoundOrder: [String] = []  // Order of sounds in default view
  var isGloballyPlaying: Bool = false
  var soloModeSound: Sound?
  var hasSelectedSounds: Bool = false
  @ObservationIgnored var soloModeOriginalVolume: Float?
  @ObservationIgnored var soloModeOriginalSelection: Bool?

  // Preview Mode (separate from solo mode for SoundSheet previews)
  var previewModeSound: Sound?
  @ObservationIgnored var previewModeOriginalStates: [String: PreviewOriginalState] = [:]

  struct PreviewOriginalState {
    let volume: Float
    let isPlaying: Bool
  }

  // A connected CarPlay scene or a car-audio output owns volume control.
  // Route detection also works in builds without the CarPlay scene entitlement.
  @ObservationIgnored private var carPlaySceneConnected = false
  @ObservationIgnored private var carAudioRouteActive = false
  private(set) var isCarPlayConnected: Bool = false

  /// Called by `CarPlayAudioBridge` when CarPlay connects or disconnects. A
  /// playing audio session is reconfigured for the new routing policy.
  @MainActor
  func setCarPlayConnected(_ connected: Bool) {
    carPlaySceneConnected = connected
    updateCarAudioConnection()
  }

  @MainActor
  func setCarAudioRouteActive(_ active: Bool, reconfigureSession: Bool = true) {
    carAudioRouteActive = active
    updateCarAudioConnection(reconfigureSession: reconfigureSession)
  }

  @MainActor
  private func updateCarAudioConnection(reconfigureSession: Bool = true) {
    let connected = carPlaySceneConnected || carAudioRouteActive
    guard isCarPlayConnected != connected else { return }
    Logger.audio.debug("AudioManager: CarPlay connection changed to: \(connected)")
    isCarPlayConnected = connected

    #if os(iOS) || os(visionOS)
      if reconfigureSession, isGloballyPlaying || previewModeSound != nil {
        setupAudioSessionForPlayback()
      }
    #endif
  }

  // Quick Mix Mode
  var isQuickMix: Bool = false
  struct QuickMixState {
    let sound: Sound
    let isSelected: Bool
    let volume: Float
  }

  @ObservationIgnored var quickMixOriginalStates: [QuickMixState] = []
  @ObservationIgnored var preQuickMixPreset: Preset?

  /// Selected-sound set last published to Now Playing, so the sound list
  /// republishes only when the selection changes.
  @ObservationIgnored private var lastPublishedSelectionSignature: String?

  /// Coalesces rapid selection and volume changes; see `soundDidChange`.
  @ObservationIgnored private var soundChangeCoalesceTask: Task<Void, Never>?

  @ObservationIgnored var modelContext: ModelContext?
  @ObservationIgnored var nowPlayingManager: (any NowPlayingPublishing)!
  @ObservationIgnored @MainActor var isInitializing = true
  /// Set once the open-time autoplay fired or playback otherwise started, so it
  /// can't re-fire on a later empty-to-selected change.
  @ObservationIgnored var launchAutoPlayHandled = false
  /// True while a preset's sound states are applied. Suppresses
  /// `deselectOtherMusicSounds` so it can't undo the preset's own selection.
  @ObservationIgnored var isApplyingPresetStates = false
  /// The launch bootstrap shared by every `loadCustomSoundsWhenReady()` caller.
  @ObservationIgnored @MainActor var launchBootstrapTask: Task<Void, Never>?
  /// Bumped per installed bootstrap task. `Task` has no identity, so waiters
  /// compare this to tell whether another caller already started a retry.
  @ObservationIgnored @MainActor var launchBootstrapGeneration = 0
  /// Set once, inside the bootstrap task, after custom sounds have loaded.
  @ObservationIgnored @MainActor var hasLoadedCustomSounds = false
  /// Number of times the custom-sound load actually ran; internal so launch
  /// tests can assert the single-flight bootstrap coalesces concurrent callers.
  @ObservationIgnored @MainActor var customSoundLoadPasses = 0
  @ObservationIgnored var customSoundObserver: AnyCancellable?
  #if os(iOS) || os(visionOS)
    @ObservationIgnored var audioSessionObserversSetup = false
    /// Whether audio was playing when an interruption began, so `.shouldResume`
    /// never starts playback the user had paused.
    @ObservationIgnored var wasPlayingWhenInterrupted = false
  #endif

  private init() {
    Logger.audio.debug("AudioManager: Initializing - START")

    Logger.audio.debug("AudioManager: About to loadSounds()")
    loadSounds()
    Logger.audio.debug("AudioManager: About to loadSavedState()")
    loadSavedState()

    // Synchronous init done; the music-exclusivity didSet may reach `shared` now.
    Self.isBootstrapping = false

    // Media controls and observers wait so init doesn't trigger the audio session.
    Task { @MainActor in
      #if canImport(NowPlaying) && !WIDGET_EXTENSION
        if #available(iOS 27, macOS 27, visionOS 27, *) {
          self.nowPlayingManager = MediaSessionNowPlaying()
          Logger.nowPlaying.debug("AudioManager: Now Playing backend is MediaSession")
        } else {
          self.nowPlayingManager = NowPlayingManager()
          Logger.nowPlaying.debug("AudioManager: Now Playing backend is MediaPlayer")
        }
      #else
        self.nowPlayingManager = NowPlayingManager()
        Logger.nowPlaying.debug("AudioManager: Now Playing backend is MediaPlayer")
      #endif

      // Let launch finish first.
      await Task.yield()

      Logger.audio.debug("AudioManager: About to setupMediaControls() (delayed)")
      self.setupMediaControls()
      Logger.audio.debug("AudioManager: About to setupNotificationObservers() (delayed)")
      self.setupNotificationObservers()

      self.isInitializing = false

      Logger.audio.debug("AudioManager: About to refreshSoundDerivedState() (after initialization)")
      self.refreshSoundDerivedState()

      Task {
        await self.analyzeCustomSoundsIfNeeded()
      }

      // A custom solo sound may not be loaded yet; loadCustomSoundsWhenReady()
      // finishes or abandons that restore.
      if self.restoreSoloModeIfNeeded() {
        // Solo restored, or pending a custom sound.
      } else {
        self.applyPresetLaunchState()
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    // A process-lifetime singleton never deinits. assumeIsolated avoids an isolated
    // deinit, which fails cross-module testability builds.
    MainActor.assumeIsolated { cleanup() }
    Logger.audio.debug("AudioManager: Deinit called, cleanup performed")
  }
}

// MARK: - Initialization Helpers

extension AudioManager {
  /// Seeds the derived selection state after sounds (re)load. Later changes
  /// arrive through each sound's `soundDidChange()` call.
  func refreshSoundDerivedState() {
    updateHasSelectedSounds()
  }

  /// Called by a `Sound` when its selection or volume changes. Coalesces bursts
  /// (a preset apply toggles many sounds) into one refresh on the main actor.
  func soundDidChange() {
    Task { @MainActor in
      self.scheduleSoundChangeRefresh()
    }
  }

  @MainActor
  private func scheduleSoundChangeRefresh() {
    soundChangeCoalesceTask?.cancel()
    soundChangeCoalesceTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(100))
      guard !Task.isCancelled else { return }
      updateHasSelectedSounds()
      PresetManager.shared.updateCurrentPresetState()
      if isQuickMix { publishCurrentWidgetSnapshot() }
      refreshNowPlayingIfSelectionChanged()
    }
  }

  /// Republishes Now Playing when the selected set changes so the artist line
  /// stays current. Quick Mix and solo publish on their own paths.
  @MainActor
  private func refreshNowPlayingIfSelectionChanged() {
    guard !isInitializing, !isQuickMix, soloModeSound == nil else { return }
    let signature =
      sounds.filter { $0.isSelected }.map(\.fileName).sorted().joined(separator: ",")
    guard signature != lastPublishedSelectionSignature else { return }
    lastPublishedSelectionSignature = signature
    nowPlayingManager.republishCurrentPreset()
  }

  func updateHasSelectedSounds() {
    let newValue = sounds.contains { $0.isSelected }

    // Nothing selected pauses playback. Checked every pass, since hasSelectedSounds
    // can already be false when playback starts; a preview defers it until it ends.
    if !newValue && isGloballyPlaying && previewModeSound == nil {
      Logger.audio.debug("AudioManager: No sounds selected - pausing playback")
      Task { @MainActor in
        // Check again when it runs. Entering solo ends a preview and queues this
        // pause, then starts the solo sound before it lands.
        guard isGloballyPlaying, !hasPlayableSelection, previewModeSound == nil else { return }
        setGlobalPlaybackState(false)
      }
    }

    if hasSelectedSounds != newValue {
      Logger.audio.debug(
        "AudioManager: hasSelectedSounds changed from \(self.hasSelectedSounds) to \(newValue)")
      hasSelectedSounds = newValue

      if newValue && !isGloballyPlaying && !sounds.isEmpty && GlobalSettings.shared.autoPlayOnLaunch
        && !isInitializing && !launchAutoPlayHandled
      {
        Logger.audio.debug(
          "AudioManager: Auto-starting playback for selected sounds (autoplay enabled)")
        launchAutoPlayHandled = true
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
      // Observe before activating on every path (previews too), so even the
      // first preview handles interruptions and route changes.
      setupAudioSessionObservers()
      setCarAudioRouteActive(
        SpatialSessionManager.isCarAudioRouteActive, reconfigureSession: false)
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
      // Assign only on change to skip the didSet work.
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
    // Quick Mix volumes are temporary.
    guard !isQuickMix else {
      Logger.audio.debug("AudioManager: Skipping state save during Quick Mix mode")
      return
    }

    // Solo forces the solo sound to selected at 1.0, so save its pre-solo values.
    let soloID = soloModeSound?.id
    let state = sounds.map { sound -> [String: Any] in
      let isSelected =
        (sound.id == soloID) ? (soloModeOriginalSelection ?? sound.isSelected) : sound.isSelected
      let volume = (sound.id == soloID) ? (soloModeOriginalVolume ?? sound.volume) : sound.volume
      return [
        "id": sound.id.uuidString,
        "fileName": sound.fileName,
        "isSelected": isSelected,
        "volume": volume,
      ]
    }
    UserDefaults.shared.set(state, forKey: "soundState")
  }

  func updateDefaultSoundOrder(from source: IndexSet, to destination: Int) {
    defaultSoundOrder.move(fromOffsets: source, toOffset: destination)
    UserDefaults.shared.set(defaultSoundOrder, forKey: "defaultSoundOrder")
    Logger.audio.debug(
      "AudioManager: Updated default sound order - moved from \(source) to \(destination)")
  }
}

extension AudioManager {
  // MARK: - Sound Management

  /// Looks up a sound by its stable `fileName` (its `UUID` changes every launch).
  /// App Intents resolve `SoundEntity` this way.
  @MainActor
  func sound(fileName: String) -> Sound? {
    sounds.first { $0.fileName == fileName }
  }

  /// Visible sounds for a preset, in its sound order. A custom preset shows its
  /// own sounds by `soundOrder`; the default preset (or none) shows all but
  /// preset-use-only sounds by `defaultSoundOrder`. Unknown sounds sort last.
  @MainActor
  func orderedVisibleSounds(for preset: Preset?) -> [Sound] {
    let visible = sounds.filter { sound in
      if let preset, !preset.isDefault {
        return preset.soundStates.contains { $0.fileName == sound.fileName }
      }
      return !sound.isPresetUseOnly
    }
    let order: [String]
    if let preset, !preset.isDefault, let soundOrder = preset.soundOrder {
      order = soundOrder
    } else {
      order = defaultSoundOrder
    }
    // An imported archive's order can repeat a name, so keep the first occurrence.
    let rank = Dictionary(
      order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return visible.sorted { (rank[$0.fileName] ?? Int.max) < (rank[$1.fileName] ?? Int.max) }
  }

  /// SF Symbols for a preset's selected sounds, for composite fallback artwork.
  /// Built from `soundStates` (sorted by `soundOrder`) so a stale `soundOrder`
  /// can't drop a sound. Deduped and capped at `limit`.
  @MainActor
  func compositeSoundIcons(for preset: Preset, limit: Int = 4) -> [String] {
    let selected = preset.soundStates.filter(\.isSelected).map(\.fileName)
    let ordered: [String]
    if let order = preset.soundOrder {
      let rank = Dictionary(
        order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      ordered = selected.sorted { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }
    } else {
      ordered = selected
    }
    let iconForFile = Dictionary(
      sounds.map { ($0.fileName, $0.systemIconName) }, uniquingKeysWith: { first, _ in first })
    return Self.dedupedIcons(ordered.compactMap { iconForFile[$0] }, limit: limit)
  }

  /// Icons for the sounds currently selected (what's actually playing), for the
  /// Now Playing / lock-screen fallback so it matches the preset's library art.
  @MainActor
  func playingSoundIcons(limit: Int = 4) -> [String] {
    Self.dedupedIcons(sounds.filter(\.isSelected).map(\.systemIconName), limit: limit)
  }

  /// Distinct icon names in order. Several sounds can share a symbol, and a
  /// montage of identical glyphs reads worse than the single icon. Capped at `limit`.
  private static func dedupedIcons(_ icons: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for icon in icons where seen.insert(icon).inserted {
      result.append(icon)
      if result.count == limit { break }
    }
    return result
  }

  func moveSound(from sourceIndex: Int, to destinationIndex: Int) {
    guard sourceIndex < sounds.count && destinationIndex <= sounds.count else {
      return
    }

    let movedSound = sounds.remove(at: sourceIndex)
    sounds.insert(movedSound, at: min(destinationIndex, sounds.count))

    Logger.audio.debug(
      "AudioManager: Moved sound '\(movedSound.fileName)' from \(sourceIndex) to \(destinationIndex)"
    )
  }

  /// Recomputes selected sounds' volumes after a volume setting changes.
  func applyVolumeSettings() {
    Logger.audio.debug("AudioManager: Updating volumes for volume settings change")

    for sound in sounds where sound.isSelected {
      sound.updateVolume()
    }
  }
}
