//
//  Sound.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import AVFoundation
import Combine
import CoreMedia
import SwiftUI
import os

/// Represents a single sound with its associated properties and playback controls.
open class Sound: NSObject, ObservableObject, Identifiable {
  public let id = UUID()
  let originalTitle: String
  let originalSystemIconName: String
  let fileName: String
  let fileExtension: String
  // `lufs` and `normalizationFactor` are `var` (not `let`) because deferred
  // LUFS analysis can complete after a custom sound is already loaded and
  // playing; `Sound+Normalization.analyzeAndUpdateLUFS` writes these from an
  // extension in another file, so they cannot be `private(set)`. Without this
  // relaxation, volume stays stuck at factor 1.0 until next app launch.
  @Published var lufs: Float?
  @Published var normalizationFactor: Float?
  let truePeakdBTP: Float?
  let needsLimiter: Bool

  // Properties for unified sound model
  let isCustom: Bool
  let fileURL: URL?
  let dateAdded: Date?
  let customSoundDataID: UUID?  // For linking to SwiftData if needed
  private var _customSoundData: CustomSoundData?

  /// SwiftData record backing a custom sound, fetched once then reused (the model object stays live).
  @MainActor var customSoundData: CustomSoundData? {
    guard let id = customSoundDataID else { return nil }
    if _customSoundData == nil {
      _customSoundData = CustomSoundManager.shared.getCustomSound(by: id)
    }
    return _customSoundData
  }

  // Computed properties that respect customizations
  var title: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveTitle(
      originalTitle: originalTitle) ?? originalTitle
  }

  var systemIconName: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveIconName(
      originalIconName: originalSystemIconName) ?? originalSystemIconName
  }

  @Published var isSelected = false {
    didSet {
      UserDefaults.shared.set(isSelected, forKey: "\(fileName)_isSelected")
      Logger.sounds.debug("Sound: \(self.fileName) -  isSelected set to \(self.isSelected)")

      // If sound was just selected, start playing it immediately when playback becomes active
      // Only do this after AudioManager is fully initialized to avoid circular dependency
      if isSelected, oldValue == false {
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }

          // Fix race condition: Ensure sound is still selected before proceeding
          guard self.isSelected else {
            Logger.sounds.debug(
              "Sound: Aborting auto-play for '\(self.fileName)' - sound was deselected")
            return
          }

          // In solo mode only the soloed sound may sound; other sounds keep
          // their selection but must stay silent. Without this, a preset's
          // selected sounds auto-play alongside a restored solo sound.
          if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
            Logger.sounds.debug(
              "Sound: Skipping auto-play for '\(self.fileName)' - solo mode active")
            return
          }

          // Already audible by intent — restarting would audibly jump
          // position. Check playbackState, not the node: a fast off/on toggle
          // leaves the node rendering its fade-out, and skipping then would
          // strand the sound selected-but-paused. play() rescues mid-fade.
          if self.playbackState == .playing {
            Logger.sounds.debug(
              "Sound: Skipping auto-play for '\(self.fileName)' - already playing")
            return
          }

          // Check if playback is active, or will become active soon
          if AudioManager.shared.isGloballyPlaying {
            Logger.sounds.debug(
              "Sound: Auto-playing newly selected sound '\(self.fileName)' during active playback")
            self.loadSound()
            self.resetSoundPosition()  // Apply randomization if enabled
            self.play()
          } else {
            // If playback isn't active yet, wait for auto-start to kick in
            Task { @MainActor [weak self] in
              await Task.yield()  // Allow auto-start to process
              guard let self = self else { return }

              // Fix race condition: Ensure sound is still selected before proceeding
              guard self.isSelected else {
                Logger.sounds.debug(
                  "Sound: Aborting delayed auto-play for '\(self.fileName)' - sound was deselected")
                return
              }

              guard AudioManager.shared.isGloballyPlaying else { return }

              // Re-check solo here too: it may have been entered during the yield.
              if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
                Logger.sounds.debug(
                  "Sound: Skipping delayed auto-play for '\(self.fileName)' - solo mode active")
                return
              }

              // Already audible by intent (see the synchronous guard above:
              // node-level isPlaying would wrongly skip mid-fade-out sounds).
              if self.playbackState == .playing {
                Logger.sounds.debug(
                  "Sound: Skipping delayed auto-play for '\(self.fileName)' - already playing")
                return
              }

              Logger.sounds.debug(
                "Sound: Auto-playing newly selected sound '\(self.fileName)' after auto-start")
              self.loadSound()
              self.resetSoundPosition()  // Apply randomization if enabled
              self.play()
            }
          }
        }
      }

      // If sound was just deselected, fade it out (preset switches read as a
      // crossfade: outgoing sounds ramp down while incoming ones ramp up)
      if !isSelected, oldValue == true {
        Logger.sounds.debug("Sound: Auto-stopping newly deselected sound '\(self.fileName)'")
        // If player exists, fade out and pause it
        if player != nil {
          pause()
        }
        // Also make sure AudioManager stops it if it's playing there
        DispatchQueue.main.async {
          if AudioManager.shared.isGloballyPlaying {
            // Force AudioManager to update its playing sounds
            AudioManager.shared.updatePlayingSounds()
          }
        }
      }
    }
  }

  /// Play/pause fades and preset crossfades all use this ramp length.
  static let fadeDuration: TimeInterval = 0.5

  var volumeDebounceTimer: Timer?

  @Published var volume: Float = 0.75 {
    didSet {
      guard volume >= 0, volume <= 1 else {
        Logger.sounds.error("Sound: Invalid volume for '\(self.fileName, privacy: .public)'")
        ErrorReporter.shared.report(AudioError.invalidVolume)
        volume = oldValue
        return
      }

      // Always update volume if player exists, not just when playing
      if player != nil {
        updateVolume()
      }

      // Debounce the save to UserDefaults (skip during Quick Mix)
      volumeDebounceTimer?.invalidate()
      volumeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
        [weak self] _ in
        guard let self = self else { return }

        // Don't persist volume changes during Quick Mix mode
        guard !AudioManager.shared.isQuickMix else {
          Logger.sounds.debug(
            "Sound: Skipping volume save for '\(self.fileName)' during Quick Mix mode")
          return
        }

        UserDefaults.shared.set(self.volume, forKey: "\(self.fileName)_volume")
        Logger.sounds.debug("Sound: \(self.fileName) final volume saved as \(self.volume)")
      }
    }
  }

  var player: SoundPlayer?

  /// Explicit playback lifecycle. `var` (not `private(set)`) because
  /// Sound+Playback maintains it from another file (same relaxation as `lufs`).
  @Published var playbackState: PlaybackState = .stopped

  enum PlaybackState {
    case stopped
    case playing
    case paused
  }

  // MARK: - Playback Facade

  /// Whether this sound is currently audible.
  var isPlaying: Bool { player?.isPlaying ?? false }

  /// Current playback position in seconds (0 when unloaded).
  var playbackPosition: TimeInterval { player?.currentTime ?? 0 }

  /// Playable duration in seconds (0 when unloaded).
  var playbackDuration: TimeInterval { player?.duration ?? 0 }

  /// Whether a player is loaded for this sound.
  var isLoaded: Bool { player != nil }

  /// Stops playback, detaches from the engine, and releases the player
  /// (preview teardown / custom-sound removal path).
  func unload() {
    if let player {
      AudioEngineManager.shared.detach(player)
    }
    player = nil
    playbackState = .stopped
  }

  private var customizationObserver: AnyCancellable?
  var isResetting = false
  private var isLoading = false

  // Metadata properties
  @Published var channelCount: Int?
  @Published var duration: TimeInterval?
  @Published var fileSize: Int64?
  @Published var fileFormat: String?

  init(
    title: String, systemIconName: String, fileName: String, fileExtension: String = "mp3",
    defaultOrder _: Int = 0, lufs: Float? = nil, normalizationFactor: Float? = nil,
    truePeakdBTP: Float? = nil, needsLimiter: Bool = false,
    isCustom: Bool = false, fileURL: URL? = nil, dateAdded: Date? = nil,
    customSoundDataID: UUID? = nil, duration: TimeInterval? = nil
  ) {
    originalTitle = title
    originalSystemIconName = systemIconName
    self.fileName = fileName
    self.fileExtension = fileExtension
    self.lufs = lufs
    self.normalizationFactor = normalizationFactor
    self.truePeakdBTP = truePeakdBTP
    self.needsLimiter = needsLimiter
    self.isCustom = isCustom
    self.fileURL = fileURL
    self.dateAdded = dateAdded
    self.customSoundDataID = customSoundDataID
    self.duration = duration

    super.init()

    // Volume and selection state will be restored by AudioManager.loadSavedState()
    // Don't load from UserDefaults here to avoid duplicate work

    // Global volume rides the engine's main mixer (AudioEngineManager), so
    // sounds no longer observe it individually.

    // Observe customization changes to trigger UI updates and volume changes
    customizationObserver = SoundCustomizationManager.shared.objectWillChange
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.objectWillChange.send()
          // Update volume if player exists to apply new customization settings
          if self?.player != nil {
            self?.updateVolume()
          }
        }
      }

    // Don't load sound immediately to avoid triggering audio session during initialization
    // loadSound() will be called lazily when needed
  }

  open func loadSound() {
    // Prevent concurrent loading
    guard !isLoading else {
      Logger.sounds.debug(
        "Sound: Already loading '\(self.fileName).\(self.fileExtension)', skipping")
      return
    }

    // If player already exists, no need to reload
    guard player == nil else {
      Logger.sounds.debug(
        "Sound: Player already loaded for '\(self.fileName).\(self.fileExtension)'")
      return
    }

    isLoading = true
    defer { isLoading = false }

    Logger.sounds.debug("Sound: Loading '\(self.fileName).\(self.fileExtension)'")

    guard let soundURL = getSoundURL() else {
      Logger.sounds.debug("Sound: File not found for '\(self.fileName).\(self.fileExtension)'")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      // Extract metadata before creating player
      extractMetadata(from: soundURL)

      let shouldLoop =
        SoundCustomizationManager.shared.getCustomization(for: fileName)?.loopSound ?? true
      let wantsSpatial = isSpatialEligible
      let loadedPlayer = try SoundPlayer(
        fileURL: soundURL, loops: shouldLoop,
        spatial: wantsSpatial,
        spatialBoostDB: wantsSpatial ? normalizationBoostDB() : 0)
      loadedPlayer.onPlaybackFinished = { [weak self] in
        self?.handleNonLoopingFinished()
      }
      if wantsSpatial {
        let placement = spatialPlacement()
        loadedPlayer.spatialPosition = AudioEngineManager.point(
          angleDegrees: placement.angle, distance: placement.distance)
      }
      player = loadedPlayer
      AudioEngineManager.shared.attach(loadedPlayer)

      // Set initial volume with normalization
      updateVolume()

      // Apply random start position if enabled (resetSoundPosition is a no-op
      // seek to 0 when randomization is disabled, matching the old load path)
      resetSoundPosition()

      Logger.sounds.debug(
        "Sound: Loaded sound '\(self.fileName).\(self.fileExtension)' with volume: \(loadedPlayer.volume)"
      )
    } catch {
      Logger.sounds.error(
        "Sound: Failed to load '\(self.fileName, privacy: .public).\(self.fileExtension, privacy: .public)': \(error, privacy: .public)"
      )
      Logger.sounds.error(
        "Sound: Error details - domain: \((error as NSError).domain, privacy: .public), code: \((error as NSError).code, privacy: .public)"
      )
      ErrorReporter.shared.report(error)
    }
  }

  func toggle() {
    isSelected.toggle()
  }

  private func updatePresetState() {
    Task { @MainActor in
      PresetManager.shared.updateCurrentPresetState()
    }
  }

  deinit {
    Logger.sounds.debug("Sound: Deinitialized '\(self.fileName)'")
    customizationObserver?.cancel()
    volumeDebounceTimer?.invalidate()
  }

  // MARK: - Spatial Arrangement (experimental, session-scoped)

  /// Whether this sound joins the spatial field right now: a session is
  /// active, preset mode (spatial is preset-only — never solo or Quick Mix),
  /// and the sound hasn't been taken out of the field this session.
  var isSpatialEligible: Bool {
    SpatialSessionManager.shared.isActive
      && AudioManager.shared.soloModeSound == nil
      && !AudioManager.shared.isQuickMix
      && SpatialSessionManager.shared.isInField(fileName)
  }

  /// This sound's placement: the session's spot, or its default ring slot.
  func spatialPlacement() -> (angle: Float, distance: Float) {
    if let placement = SpatialSessionManager.shared.placement(for: fileName) {
      return (placement.angle, placement.distance)
    }
    let slot = AudioEngineManager.defaultSpatialPlacement(for: "\(fileName).\(fileExtension)")
    return (slot.angleDegrees, slot.distance)
  }

  /// Live-moves the sound in the field; optionally remembers the spot for the
  /// rest of the session (in memory only — synchronous, so the mixer re-reads
  /// fresh data immediately and released dots don't snap back).
  func setSpatialPlacement(angleDegrees: Float, distance: Float, persist: Bool) {
    let point = AudioEngineManager.point(angleDegrees: angleDegrees, distance: distance)
    player?.spatialPosition = point
    if let player, player.isSpatial {
      player.node.position = point
    }
    if persist {
      SpatialSessionManager.shared.setPlacement(
        angle: angleDegrees, distance: distance, for: fileName)
    }
  }

  /// Whether the sound can join the field right now: short sounds fold in
  /// memory; long ones need their rendered mono cache (see prepareForSpatial).
  var isSpatialReady: Bool {
    if (duration ?? 0) <= SoundPlayer.bufferThreshold { return true }
    guard let url = getSoundURL() else { return false }
    return SpatialAudioCache.existingCache(for: url, boostDB: normalizationBoostDB()) != nil
  }

  /// Renders the mono cache a long sound needs before joining the field.
  @MainActor
  func prepareForSpatial() async -> Bool {
    guard let url = getSoundURL() else { return false }
    do {
      _ = try await SpatialAudioCache.renderMonoCache(for: url, boostDB: normalizationBoostDB())
      return true
    } catch {
      Logger.sounds.error(
        "Sound: Spatial render failed for '\(self.fileName, privacy: .public)': \(error, privacy: .public)"
      )
      return false
    }
  }

  /// Rebuilds the player when spatial participation changes, preserving playback.
  func rebuildPlayerForSpatialChange() {
    guard isLoaded else { return }
    let wasPlaying = playbackState == .playing
    unload()
    if wasPlaying {
      loadSound()
      play()
    }
  }

  // MARK: - Playback Completion

  /// Handles a non-looping sound reaching its end. SoundPlayer fires this on
  /// the main queue; looping schedules never finish.
  func handleNonLoopingFinished() {
    playbackState = .stopped

    // Loop toggled on after load (player not reloaded yet): the old delegate
    // ended silently in that case, so match it.
    let shouldLoop =
      SoundCustomizationManager.shared.getCustomization(for: fileName)?.loopSound ?? true
    guard !shouldLoop else { return }

    Logger.sounds.debug("Sound: Non-looping sound '\(self.fileName)' finished playing")

    if AudioManager.shared.soloModeSound?.id == id {
      Logger.sounds.debug(
        "Sound: Non-looping sound in solo mode finished, pausing global playback")
      // Reset the sound position for next play; stay in solo mode but pause.
      resetSoundPosition()
      Task { @MainActor in
        AudioManager.shared.setGlobalPlaybackState(false)
      }
    } else {
      // Normal mode - deselect the sound
      isSelected = false
    }
  }
}
