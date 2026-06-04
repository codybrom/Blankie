//
//  NowPlayingManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Manages Now Playing info for media playback controls
@MainActor
final class NowPlayingManager {
  var nowPlayingInfo: [String: Any] = [:]

  private var isSetup = false
  var currentArtworkId: UUID?
  var currentStaticArtworkPath: String?
  var staticArtworkTask: Task<Void, Never>?
  #if os(iOS)
    var currentAnimatedLoopPath: String?
    var currentAnimatedPreviewPath: String?
    // ODR download + Documents-cache tasks in flight, keyed by bundled id.
    // Lets duplicate triggers for the same animated artwork coalesce instead
    // of spawning parallel downloads and cache-copy attempts.
    var animatedArtworkDownloadTasks: [String: Task<Void, Never>] = [:]
  #endif
  private var updateTimer: Timer?
  // Drives elapsed-time republishing so the system scrubber (lock screen +
  // CarPlay) snaps back to the start each time the longest sound loops.
  // Independent of `updateTimer`.
  private var progressTimer: Timer?
  // Last elapsed/duration we anchored the scrubber to. The system extrapolates
  // smoothly between writes, so we only re-anchor when the elapsed time jumps
  // backward (a sound loop wrapped) or the duration changes (sleep timer
  // started/extended/stopped, or the represented source changed) —
  // re-anchoring every tick makes the bar stutter. `lastObservedElapsed < 0`
  // forces the first tick after (re)start to anchor.
  private var lastObservedElapsed: TimeInterval = -1
  private var lastObservedDuration: TimeInterval = 0
  private var cancellables = Set<AnyCancellable>()
  private var lastPresetId: UUID?  // Track last preset to avoid unnecessary artwork updates
  private var lastSoloSoundId: UUID?  // Track last solo sound so its icon artwork refreshes

  init() {
    // Don't setup immediately to avoid triggering audio session
    GlobalSettings.shared.$lockScreenBackgroundEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.republishCurrentPreset()
      }
      .store(in: &cancellables)

    #if os(iOS)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(animatedArtworkConditionChanged),
        name: UIAccessibility.reduceMotionStatusDidChangeNotification,
        object: nil
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(animatedArtworkConditionChanged),
        name: Notification.Name.NSProcessInfoPowerStateDidChange,
        object: nil
      )
    #endif
  }

  deinit {
    staticArtworkTask?.cancel()
    updateTimer?.invalidate()
    progressTimer?.invalidate()
    cancellables.removeAll()
    NotificationCenter.default.removeObserver(self)
  }

  private func setupNowPlaying() {
    guard !isSetup else { return }
    debugLog("🎵 NowPlayingManager: Setting up Now Playing info")
    isSetup = true

    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0  // Start as paused

    if let artwork = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
  }

  func updateInfo(
    preset: Preset? = nil,
    presetName: String? = nil,
    creatorName: String? = nil,
    artworkId: UUID? = nil,
    isPlaying: Bool
  ) {
    // Debounce rapid successive updates during initialization
    updateTimer?.invalidate()
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
      Task { @MainActor in
        await self?.performNowPlayingUpdate(
          preset: preset, presetName: presetName, creatorName: creatorName, artworkId: artworkId,
          isPlaying: isPlaying
        )
      }
    }
  }

  private func performNowPlayingUpdate(
    preset: Preset?,
    presetName: String?,
    creatorName: String?,
    artworkId: UUID?,
    isPlaying: Bool
  ) async {
    setupNowPlaying()

    let resolvedPresetName = preset?.name ?? presetName
    let resolvedCreatorName = preset?.creatorName ?? creatorName

    let displayInfo = getDisplayInfo(
      presetName: resolvedPresetName, creatorName: resolvedCreatorName)
    debugLog(
      "🎵 NowPlayingManager: Updating Now Playing info with title: \(displayInfo.title), artist: \(displayInfo.artist)"
    )

    // A full (artwork) update is needed when the preset OR the solo sound
    // changes. Solo sounds have no preset, so tracking only the preset id would
    // miss solo→solo transitions and leave the previous sound's icon up.
    let soloSoundId = AudioManager.shared.soloModeSound?.id
    let presetChanged = preset?.id != lastPresetId
    let soloChanged = soloSoundId != lastSoloSoundId

    updateBasicInfo(displayInfo: displayInfo)
    updateAlbumAndDuration(creatorName: resolvedCreatorName)
    updatePlaybackRate(isPlaying: isPlaying)

    // Only update artwork when the preset/solo sound changes, to avoid
    // restarting animated artwork on every incremental tick.
    if presetChanged || soloChanged {
      if let soloSound = AudioManager.shared.soloModeSound {
        // Solo mode: show the sound's own icon, not the last preset's artwork.
        applySoloArtwork(for: soloSound)
        #if os(iOS)
          removeAnimatedArtwork()
        #endif
      } else {
        // CRITICAL: Load static artwork synchronously to avoid double-publishing
        // If we load async, the artwork loads after we publish, triggering a second update that restarts animated artwork
        await loadStaticArtworkSync(from: preset, fallbackArtworkId: artworkId)
        #if os(iOS)
          updateAnimatedArtwork(for: preset)
        #endif
      }
      lastPresetId = preset?.id
      lastSoloSoundId = soloSoundId

      // Full update when preset changes (only published once, after both artworks are ready)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    } else {
      // Incremental update - only update specific keys to avoid restarting animated artwork
      // CRITICAL: We update keys in-place on the existing dictionary to preserve artwork objects
      let center = MPNowPlayingInfoCenter.default()

      if center.nowPlayingInfo != nil {
        debugLog("🎵 NowPlayingManager: Incremental update (preserving animated artwork)")
        // Update only non-artwork keys in-place
        center.nowPlayingInfo?[MPMediaItemPropertyTitle] = nowPlayingInfo[MPMediaItemPropertyTitle]
        center.nowPlayingInfo?[MPMediaItemPropertyArtist] =
          nowPlayingInfo[MPMediaItemPropertyArtist]
        center.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] =
          nowPlayingInfo[MPMediaItemPropertyAlbumTitle]
        center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
          nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]
        center.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] =
          nowPlayingInfo[MPMediaItemPropertyPlaybackDuration]
        center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
          nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime]
      } else {
        // No existing info (iOS cleared it), do full update
        debugLog("🎵 NowPlayingManager: Full update (iOS cleared nowPlayingInfo)")
        center.nowPlayingInfo = nowPlayingInfo
      }
    }

    // Keep the scrubber tracking the looping sounds only while playing.
    if isPlaying {
      startProgressUpdates()
    } else {
      stopProgressUpdates()
    }
  }

  /// Set the lock-screen artwork to the soloed sound's rendered icon. Clears
  /// the cached preset-artwork identity so returning to a preset reloads it.
  private func applySoloArtwork(for sound: Sound) {
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    if let artwork = soloArtwork(for: sound) {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    } else if let fallback = loadArtwork() {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = fallback
    }
  }

  private func updateBasicInfo(displayInfo: (title: String, artist: String)) {
    nowPlayingInfo[MPMediaItemPropertyTitle] = displayInfo.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = displayInfo.artist
  }

  private func updateAlbumAndDuration(creatorName: String?) {
    if let soloSound = AudioManager.shared.soloModeSound {
      updateSoloModeInfo(soloSound: soloSound)
    } else {
      updatePresetModeInfo(creatorName: creatorName)
    }
  }

  private func updateSoloModeInfo(soloSound: Sound) {
    // Only add an album line when the artist line is a credited author;
    // otherwise the artist already says "Blankie" and the album is redundant.
    if soloSound.creditedAuthor != nil {
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie"
    } else {
      nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
    }
    applyProgressAnchorToInfo()
  }

  private func updatePresetModeInfo(creatorName: String?) {
    updateAlbumTitle(creatorName: creatorName)
    updateDurationFromPlayingSounds()
  }

  private func updateAlbumTitle(creatorName: String?) {
    // Without a creator the artist line already lists the sounds (or
    // "Blankie"), so an extra album line is redundant.
    guard creatorName != nil else {
      nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
      return
    }
    let activeSounds = AudioManager.shared.sounds.filter { $0.player?.isPlaying == true }
    if !activeSounds.isEmpty {
      let soundNames = activeSounds.map { $0.title }.joined(separator: ", ")
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = soundNames
    } else {
      nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Blankie"
    }
  }

  private func updateDurationFromPlayingSounds() {
    applyProgressAnchorToInfo()
  }

  /// Writes the current progress anchor into the local `nowPlayingInfo` snapshot
  /// (falling back to indeterminate). Used by the initial publish; the periodic
  /// tick re-anchors the live center afterward.
  private func applyProgressAnchorToInfo() {
    if let anchor = currentProgressAnchor() {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = anchor.duration
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = anchor.elapsed
    } else {
      setInfiniteDuration()
    }
  }

  /// The elapsed/duration the scrubber should represent right now, or `nil` for
  /// an indeterminate bar. Priority: an active sleep timer (real, slow,
  /// meaningful progress that ends where playback stops) wins over the looping
  /// audio, then the solo sound, then the longest selected sound's loop.
  private func currentProgressAnchor() -> (elapsed: TimeInterval, duration: TimeInterval)? {
    let sleepTimer = TimerManager.shared
    if sleepTimer.isTimerActive, sleepTimer.selectedDuration > 0 {
      let elapsed = sleepTimer.selectedDuration - sleepTimer.remainingTime
      return (max(0, elapsed), sleepTimer.selectedDuration)
    }

    let player: AVAudioPlayer?
    if let soloSound = AudioManager.shared.soloModeSound {
      player = soloSound.player
    } else {
      // Use active (selected) sounds, not only playing ones, so we still track
      // time when paused; mirror the "longest selected sound" choice.
      player =
        AudioManager.shared.sounds
        .filter { $0.isSelected }
        .max { ($0.player?.duration ?? 0) < ($1.player?.duration ?? 0) }?
        .player
    }

    guard let player, player.duration > 0 else { return nil }
    return (player.currentTime, player.duration)
  }

  private func setInfiniteDuration() {
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
  }

  private func updatePlaybackRate(isPlaying: Bool) {
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
  }

  func republishCurrentPreset() {
    let preset = PresetManager.shared.currentPreset
    updateInfo(
      preset: preset,
      presetName: preset?.name,
      creatorName: preset?.creatorName,
      artworkId: preset?.artworkId,
      isPlaying: AudioManager.shared.isGloballyPlaying
    )
  }

  /// Force a full refresh of Now Playing info including artwork
  /// Used when artwork changes on the same preset
  func forceRefresh(
    preset: Preset,
    isPlaying: Bool
  ) {
    lastPresetId = nil  // Clear cache to force full artwork update
    updateInfo(
      preset: preset,
      presetName: preset.name,
      creatorName: preset.creatorName,
      artworkId: preset.artworkId,
      isPlaying: isPlaying
    )
  }

  func updatePlaybackState(isPlaying: Bool) {
    setupNowPlaying()  // Ensure setup is done before updating

    // Ensure nowPlayingInfo dictionary exists
    if nowPlayingInfo.isEmpty {
      // Recreate basic info if needed
      nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
      nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    }

    // Update playback state
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0  // Infinite for ambient sounds

    // Update the now playing info
    debugLog(
      "🎵 NowPlayingManager: Updating now playing state to \(isPlaying), playbackRate: \(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

    if isPlaying {
      startProgressUpdates()
    } else {
      stopProgressUpdates()
    }
  }

  func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
    guard !nowPlayingInfo.isEmpty else { return }

    // Ensure playback rate reflects current state
    let isPlaying = AudioManager.shared.isGloballyPlaying

    // Keep our local snapshot in sync so the next full publish is correct.
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    let center = MPNowPlayingInfoCenter.default()
    if center.nowPlayingInfo != nil {
      // Update only the timing/rate keys in-place. Replacing the whole dict
      // (which carries the static/animated artwork objects) would restart the
      // animated lock-screen artwork on every tick.
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
      center.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = duration
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    } else {
      // iOS cleared it — do a full publish to re-establish info + artwork.
      center.nowPlayingInfo = nowPlayingInfo
    }
  }

  /// Starts watching the active progress source (sleep timer or looping sound)
  /// and re-anchors the system scrubber when it wraps or its duration changes.
  /// The system extrapolates elapsed time smoothly from `playbackRate` between
  /// writes, so we publish only at those moments (and once up front) to keep the
  /// bar from stuttering.
  private func startProgressUpdates() {
    stopProgressUpdates()
    lastObservedElapsed = -1  // Force the first tick to anchor.
    publishProgressTick()  // Anchor immediately so the bar doesn't lag.

    // Poll faster than we publish: reading `currentTime` is cheap and a tighter
    // poll detects the wrap sooner, so the snap-back is crisp.
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.publishProgressTick()
      }
    }
    // Track during scrolling/interaction too.
    RunLoop.main.add(timer, forMode: .common)
    progressTimer = timer
  }

  private func stopProgressUpdates() {
    progressTimer?.invalidate()
    progressTimer = nil
    lastObservedElapsed = -1
    lastObservedDuration = 0
  }

  /// Re-anchors the system scrubber only on the first tick, a loop wrap, or a
  /// duration change (sleep timer started/extended/stopped, source switched).
  private func publishProgressTick() {
    guard AudioManager.shared.isGloballyPlaying else {
      stopProgressUpdates()
      return
    }

    guard let anchor = currentProgressAnchor() else { return }
    let elapsed = anchor.elapsed
    let duration = anchor.duration
    defer {
      lastObservedElapsed = elapsed
      lastObservedDuration = duration
    }

    let isFirst = lastObservedElapsed < 0
    let wrapped = elapsed < lastObservedElapsed - 0.5  // sound loop restarted
    let durationChanged = abs(duration - lastObservedDuration) > 0.5
    guard isFirst || wrapped || durationChanged else { return }

    updateProgress(currentTime: elapsed, duration: duration)
  }

  func clear() {
    stopProgressUpdates()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    staticArtworkTask?.cancel()
    staticArtworkTask = nil
    currentArtworkId = nil
    currentStaticArtworkPath = nil
    lastPresetId = nil
    lastSoloSoundId = nil
    #if os(iOS)
      removeAnimatedArtwork()
    #endif
  }
}
