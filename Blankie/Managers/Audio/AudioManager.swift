//
//  AudioManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import MediaPlayer
import Observation
import SwiftData
import SwiftUI
import os

@Observable
class AudioManager {
  static let shared = AudioManager()
  /// True only during `shared`'s synchronous init. A plain static (not an
  /// instance flag) so the music-exclusivity didSet can read it without
  /// re-entering the still-initializing `shared` lazy static and trapping.
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

  // CarPlay connection state, pushed in by `CarPlayAudioBridge`. Stays `false`
  // on platforms that don't build CarPlay support. Read by
  // `setupAudioSessionForPlayback` to configure the audio session appropriately.
  private(set) var isCarPlayConnected: Bool = false

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
  var isQuickMix: Bool = false
  struct QuickMixState {
    let sound: Sound
    let isSelected: Bool
    let volume: Float
  }

  @ObservationIgnored var quickMixOriginalStates: [QuickMixState] = []
  @ObservationIgnored var preQuickMixPreset: Preset?

  /// Signature of the last selected-sound set published to Now Playing. Lets the
  /// sound-change observer republish the system/CarPlay "Now Playing" sound list
  /// only when the selection actually changes (not on every volume/state tick).
  @ObservationIgnored private var lastPublishedSelectionSignature: String?

  /// Coalesces rapid sound selection/volume changes into one derived-state
  /// refresh (replaces the old per-Sound Combine observer); see `soundDidChange`.
  @ObservationIgnored private var soundChangeCoalesceTask: Task<Void, Never>?

  @ObservationIgnored var modelContext: ModelContext?
  @ObservationIgnored var nowPlayingManager: NowPlayingManager!
  @ObservationIgnored @MainActor var isInitializing = true
  /// True while a preset's sound states are being applied. Suppresses the
  /// music-exclusivity enforcement (`deselectOtherMusicSounds`), which would
  /// otherwise fight the preset restoring its own selection set.
  @ObservationIgnored var isApplyingPresetStates = false
  /// Set once custom sounds have been loaded from SwiftData. Guards against a
  /// second full reload — on the CarPlay build both `IOSAppDelegate` and
  /// `AppSetup` call `loadCustomSoundsWhenReady()`, and re-running the load
  /// would re-instantiate custom `Sound` objects that the UI/preset still
  /// references, orphaning the originals (which then can't be stopped).
  @ObservationIgnored @MainActor var hasLoadedCustomSounds = false
  @ObservationIgnored var customSoundObserver: AnyCancellable?
  #if os(iOS) || os(visionOS)
    @ObservationIgnored var audioSessionObserversSetup = false
    /// Whether playback was active when an audio-session interruption began, so
    /// the `.shouldResume` hint only resumes audio the user had actually going —
    /// a call arriving while paused must not start the app playing on its own.
    @ObservationIgnored var wasPlayingWhenInterrupted = false
  #endif

  private init() {
    Logger.audio.debug("AudioManager: Initializing - START")

    // Only load sounds and state immediately - delay media controls and observers
    Logger.audio.debug("AudioManager: About to loadSounds()")
    loadSounds()
    Logger.audio.debug("AudioManager: About to loadSavedState()")
    loadSavedState()

    // Synchronous init done; the music-exclusivity didSet may reach `shared` now.
    Self.isBootstrapping = false

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

      Logger.audio.debug("AudioManager: About to refreshSoundDerivedState() (after initialization)")
      self.refreshSoundDerivedState()

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
  /// Seeds the derived selection state after sounds (re)load. Sounds are
  /// `@Observable` and call `soundDidChange()` from their own `isSelected` /
  /// `volume` didSet, so no per-Sound observers are needed — newly loaded
  /// sounds participate automatically.
  func refreshSoundDerivedState() {
    updateHasSelectedSounds()
  }

  /// Called by a `Sound` whenever its selection or volume changes. Coalesces
  /// rapid changes (e.g. applying a preset toggles many sounds) into a single
  /// refresh of the derived selection flag, preset divergence, and Now Playing.
  /// Replaces the old per-Sound `objectWillChange` debounce. Hops to the main
  /// actor first so the coalesce task is only ever touched there.
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
      refreshNowPlayingIfSelectionChanged()
    }
  }

  /// Republishes Now Playing when the selected-sound set changes so the artist
  /// line stays current as sounds toggle — not only on global play/pause. Quick
  /// Mix and solo republish on their own paths, so they're skipped here.
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

    // While soloing, the solo sound's live values are forced (selected, volume
    // 1.0); persist its saved pre-solo originals instead so a background/quit
    // mid-solo doesn't corrupt the user's real mix on the next launch.
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

  @MainActor
  func getVisibleSounds() -> [Sound] {
    sounds
  }

  /// Visible sounds for a preset context, ordered by the active sound order —
  /// the single source for the mixer grid, the menu bar list, and iOS. A custom
  /// (non-default) preset shows only its own sounds in its `soundOrder`; the
  /// default preset (or none) shows everything but preset-use-only sounds, in
  /// `defaultSoundOrder`. Unknown sounds sort last.
  @MainActor
  func orderedVisibleSounds(for preset: Preset?) -> [Sound] {
    let visible = getVisibleSounds().filter { sound in
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
    let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    return visible.sorted { (rank[$0.fileName] ?? Int.max) < (rank[$1.fileName] ?? Int.max) }
  }

  /// SF Symbol names for a preset's *selected* sounds, in the preset's order,
  /// for composite fallback artwork — a montage of the sounds it plays. Resolved
  /// from `soundStates` directly (ordered by `soundOrder` when present) so a
  /// stale or partial `soundOrder` can't drop selected sounds. Deduped and
  /// capped at `limit`; unknown file names are skipped.
  @MainActor
  func compositeSoundIcons(for preset: Preset, limit: Int = 4) -> [String] {
    let selected = preset.soundStates.filter(\.isSelected).map(\.fileName)
    let ordered: [String]
    if let order = preset.soundOrder {
      let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
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

  /// Move a sound to a new position
  func moveSound(from sourceIndex: Int, to destinationIndex: Int) {
    guard sourceIndex < sounds.count && destinationIndex <= sounds.count else {
      return
    }

    // Move sound in the array
    let movedSound = sounds.remove(at: sourceIndex)
    sounds.insert(movedSound, at: min(destinationIndex, sounds.count))

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
