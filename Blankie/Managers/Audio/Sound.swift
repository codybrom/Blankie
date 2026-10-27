//
//  Sound.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import AVFoundation
import CoreMedia
import Observation
import SwiftUI
import os

/// One built-in or custom sound, with its playback state and customizations.
@Observable
open class Sound: NSObject, Identifiable {
  public let id = UUID()
  let originalTitle: String
  let originalSystemIconName: String
  let fileName: String
  // `fileExtension` and `fileURL` are `var` so an in-place AAC conversion can repoint
  // a custom sound at its re-encoded file while views keep observing this instance.
  var fileExtension: String
  // `var` because deferred LUFS analysis (Sound+Normalization) can finish after
  // the sound is already loaded and playing.
  var lufs: Float?
  var normalizationFactor: Float?
  let truePeakdBTP: Float?
  let needsLimiter: Bool
  /// Music tag default from sounds.json (false for custom sounds); the
  /// `isMusic` customization overrides it.
  let isMusicDefault: Bool

  let isCustom: Bool
  var fileURL: URL?
  let dateAdded: Date?
  let customSoundDataID: UUID?
  @ObservationIgnored private var _customSoundData: CustomSoundData?

  /// SwiftData record backing a custom sound, fetched once then reused (the model object stays live).
  @MainActor var customSoundData: CustomSoundData? {
    guard let id = customSoundDataID else { return nil }
    if _customSoundData == nil {
      _customSoundData = CustomSoundManager.shared.getCustomSound(by: id)
    }
    return _customSoundData
  }

  var title: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveTitle(
      originalTitle: originalTitle) ?? originalTitle
  }

  /// Display title. Unrenamed built-in sounds localize under `sound.<fileName>`;
  /// custom and renamed sounds show the user's title verbatim.
  var localizedTitle: String {
    guard !isCustom, title == originalTitle else { return title }
    return NSLocalizedString(
      "sound.\(fileName)", value: originalTitle, comment: "Built-in sound name")
  }

  var systemIconName: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveIconName(
      originalIconName: originalSystemIconName) ?? originalSystemIconName
  }

  /// Hidden from the Library's Sounds list and the All Sounds grid; still
  /// usable inside presets. Non-looping one-shots are always preset-only.
  var isPresetUseOnly: Bool {
    let customization = SoundCustomizationManager.shared.getCustomization(for: fileName)
    return (customization?.isPresetUseOnly ?? false) || !(customization?.loopSound ?? true)
  }

  /// Tagged as music. A preset plays at most one music sound at a time (the
  /// last one selected wins). Seeded from sounds.json, overridable per sound.
  var isMusic: Bool {
    SoundCustomizationManager.shared.getCustomization(for: fileName)?.isMusic ?? isMusicDefault
  }

  var isSelected = false {
    didSet {
      UserDefaults.shared.set(isSelected, forKey: "\(fileName)_isSelected")

      // A newly selected sound starts playing once playback is active.
      if isSelected, oldValue == false {
        // A preset holds at most one music sound (last selected wins). Synchronous so
        // the outgoing sound fades as this one comes in; skipped during bootstrap.
        if isMusic, !AudioManager.isBootstrapping {
          AudioManager.shared.deselectOtherMusicSounds(except: self)
        }

        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }

          guard self.isSelected else {
            Logger.sounds.debug(
              "Sound: Aborting auto-play for '\(self.fileName)' - sound was deselected")
            return
          }

          // In solo mode, other selected sounds keep their selection but stay silent.
          if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
            Logger.sounds.debug(
              "Sound: Skipping auto-play for '\(self.fileName)' - solo mode active")
            return
          }

          // Restarting a playing sound would jump its position. Check playbackState,
          // not the node: mid-fade-out the node still reports playing (play() resumes it).
          if self.playbackState == .playing {
            Logger.sounds.debug(
              "Sound: Skipping auto-play for '\(self.fileName)' - already playing")
            return
          }

          if AudioManager.shared.isGloballyPlaying {
            Logger.sounds.debug(
              "Sound: Auto-playing newly selected sound '\(self.fileName)' during active playback")
            self.loadSound()
            self.resetSoundPosition()  // Apply randomization if enabled
            self.play()
          } else {
            // Playback may be about to auto-start; check again after a yield.
            Task { @MainActor [weak self] in
              await Task.yield()
              guard let self = self else { return }

              guard self.isSelected else {
                Logger.sounds.debug(
                  "Sound: Aborting delayed auto-play for '\(self.fileName)' - sound was deselected")
                return
              }

              guard AudioManager.shared.isGloballyPlaying else { return }

              // Solo mode may have started during the yield.
              if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
                Logger.sounds.debug(
                  "Sound: Skipping delayed auto-play for '\(self.fileName)' - solo mode active")
                return
              }

              // Check playbackState, not the node (see the guard above).
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

      // A deselected sound fades out, so preset switches read as a crossfade.
      if !isSelected, oldValue == true {
        Logger.sounds.debug("Sound: Auto-stopping newly deselected sound '\(self.fileName)'")
        if player != nil {
          pause()
        }
        DispatchQueue.main.async {
          if AudioManager.shared.isGloballyPlaying {
            AudioManager.shared.updatePlayingSounds()
          }
        }
      }

      // Refresh selection state, preset divergence and Now Playing. Skipped during
      // bootstrap, where reaching `shared` would re-enter its still-running init.
      if !AudioManager.isBootstrapping {
        AudioManager.shared.soundDidChange()
      }
    }
  }

  /// Play/pause fades and preset crossfades all use this ramp length.
  static let fadeDuration: TimeInterval = 0.5

  /// Remote-command pauses cut instantly. Control Center derives "playing" from
  /// live engine I/O, so any audible ramp makes its transport button flip back and forth.
  static let remotePauseFadeDuration: TimeInterval = 0

  // nonisolated(unsafe): only ever mutated on the main actor; the nonisolated
  // deinit is the last reference, so invalidating it there is race-free.
  @ObservationIgnored nonisolated(unsafe) var volumeDebounceTimer: Timer?

  /// Saves a pending debounced volume now (the app is quitting or suspending).
  func flushPendingVolumeSave() {
    volumeDebounceTimer?.fire()
  }

  var volume: Float = 0.75 {
    didSet {
      guard volume >= 0, volume <= 1 else {
        Logger.sounds.error("Sound: Invalid volume for '\(self.fileName, privacy: .public)'")
        ErrorReporter.shared.report(AudioError.invalidVolume)
        volume = oldValue
        return
      }

      if player != nil {
        updateVolume()
      }

      // Debounce the save to UserDefaults (skip during Quick Mix)
      volumeDebounceTimer?.invalidate()
      volumeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
        [weak self] _ in
        // The timer fires on the main run loop; recover that isolation statically.
        MainActor.assumeIsolated {
          guard let self = self else { return }

          guard !AudioManager.shared.isQuickMix else {
            Logger.sounds.debug(
              "Sound: Skipping volume save for '\(self.fileName)' during Quick Mix mode")
            return
          }

          UserDefaults.shared.set(self.volume, forKey: "\(self.fileName)_volume")
        }
      }

      // Re-evaluate preset divergence (a preset records each sound's volume).
      if !AudioManager.isBootstrapping {
        AudioManager.shared.soundDidChange()
      }
    }
  }

  @ObservationIgnored var player: SoundPlayer?

  /// Explicit playback lifecycle. `var` because Sound+Playback maintains it from another file.
  var playbackState: PlaybackState = .stopped

  enum PlaybackState {
    case stopped
    case playing
    case paused
  }

  // MARK: - Playback Facade

  var isPlaying: Bool { player?.isPlaying ?? false }

  /// Current playback position in seconds (0 when unloaded).
  var playbackPosition: TimeInterval { player?.currentTime ?? 0 }

  /// Playable duration in seconds (0 when unloaded).
  var playbackDuration: TimeInterval { player?.duration ?? 0 }

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

  @ObservationIgnored var isResetting = false
  @ObservationIgnored private var isLoading = false
  // Memoized spatial-cache existence (not private: re-analysis in
  // Sound+Normalization invalidates it when the baked boost changes).
  @ObservationIgnored var spatialReadyCache: Bool?

  var channelCount: Int?
  var duration: TimeInterval?
  var fileSize: Int64?
  var fileFormat: String?

  init(
    title: String, systemIconName: String, fileName: String, fileExtension: String = "mp3",
    defaultOrder _: Int = 0, lufs: Float? = nil, normalizationFactor: Float? = nil,
    truePeakdBTP: Float? = nil, needsLimiter: Bool = false,
    isMusic: Bool = false,
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
    self.isMusicDefault = isMusic
    self.isCustom = isCustom
    self.fileURL = fileURL
    self.dateAdded = dateAdded
    self.customSoundDataID = customSoundDataID
    self.duration = duration

    super.init()

    // AudioManager.loadSavedState() restores volume and selection. The player loads
    // lazily so creating a sound doesn't activate the audio session.
  }

  open func loadSound() {
    guard !isLoading else {
      Logger.sounds.debug(
        "Sound: Already loading '\(self.fileName).\(self.fileExtension)', skipping")
      return
    }

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

      updateVolume()

      // Random start position if enabled (otherwise seeks to 0).
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
    volumeDebounceTimer?.invalidate()
  }

  // MARK: - Spatial Arrangement (experimental, session-scoped)

  /// Whether this sound joins the spatial field: a session is active, a preset is
  /// playing (not solo or Quick Mix), and the sound is still in the field.
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

  /// Moves the sound in the field. `persist` stores the spot in memory for the session,
  /// synchronously, so the mixer re-reads it at once and released dots stay put.
  @MainActor
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

  /// Short sounds fold to mono in memory; long ones need their rendered mono cache
  /// (see prepareForSpatial). Memoized because the mixer reads this at ~10 Hz.
  var isSpatialReady: Bool {
    // Unknown duration counts as long (the player would stream it unspatialized).
    if let duration, duration <= SoundPlayer.bufferThreshold { return true }
    if let cached = spatialReadyCache { return cached }
    guard let url = getSoundURL() else { return false }
    let ready = SpatialAudioCache.existingCache(for: url, boostDB: normalizationBoostDB()) != nil
    spatialReadyCache = ready
    return ready
  }

  /// Renders the mono cache a long sound needs before joining the field.
  @MainActor
  func prepareForSpatial() async -> Bool {
    guard let url = getSoundURL() else { return false }
    do {
      _ = try await SpatialAudioCache.renderMonoCache(for: url, boostDB: normalizationBoostDB())
      spatialReadyCache = true
      return true
    } catch {
      Logger.sounds.error(
        "Sound: Spatial render failed for '\(self.fileName, privacy: .public)': \(error, privacy: .public)"
      )
      return false
    }
  }

  /// Rebuilds the player when spatial participation changes, preserving the
  /// position of a playing or paused sound (stopped sounds reload fresh) and
  /// resuming if it was audibly playing (and playback is globally on).
  @MainActor
  func rebuildPlayerForSpatialChange() {
    guard isLoaded else { return }
    let priorState = playbackState
    let position = player?.currentTime ?? 0
    unload()
    loadSound()
    if priorState != .stopped {
      restorePlaybackPosition(position)
    }
    if priorState == .playing, AudioManager.shared.isGloballyPlaying {
      play()
    }
  }

  /// Seeks a freshly (re)loaded player to a position captured before a
  /// rebuild. Seconds, not frames (a mono cache's frame count can differ);
  /// marks .paused so playSelected doesn't re-randomize it as "stopped".
  func restorePlaybackPosition(_ seconds: TimeInterval) {
    guard let player, seconds > 0 else { return }
    player.seek(toFrame: AVAudioFramePosition(seconds * player.sampleRate))
    playbackState = .paused
  }

  // MARK: - Playback Completion

  /// Handles a non-looping sound reaching its end. SoundPlayer fires this on
  /// the main queue; looping schedules never finish.
  func handleNonLoopingFinished() {
    playbackState = .stopped

    // Loop toggled on after load (player not reloaded yet): just stop.
    let shouldLoop =
      SoundCustomizationManager.shared.getCustomization(for: fileName)?.loopSound ?? true
    guard !shouldLoop else { return }

    Logger.sounds.debug("Sound: Non-looping sound '\(self.fileName)' finished playing")

    if AudioManager.shared.soloModeSound?.id == id {
      Logger.sounds.debug(
        "Sound: Non-looping sound in solo mode finished, pausing global playback")
      // An exhausted node still reports isPlaying, which makes resetSoundPosition()
      // skip the rewind. Stop it first.
      player?.stop()
      resetSoundPosition()
      Task { @MainActor in
        AudioManager.shared.setGlobalPlaybackState(false)
      }
    } else {
      // Stop and rewind before deselecting so the deselect fade (or a re-tap)
      // doesn't run on a spent schedule (same isPlaying issue as above).
      player?.stop()
      resetSoundPosition()
      isSelected = false
    }
  }
}
