//
//  AudioManager+Notifications.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import SwiftUI
import os

// MARK: - Notification Observers

extension AudioManager {
  func setupNotificationObservers() {
    #if os(iOS) || os(visionOS)
      setupIOSNotificationObservers()
    #elseif os(macOS)
      setupMacOSNotificationObservers()
    #endif
  }

  #if os(iOS) || os(visionOS)
    private func setupIOSNotificationObservers() {
      setupTerminationObserver()
      setupBackgroundObservers()
      // Route observation does not activate audio. Keep UI policy current even
      // before the first play, including builds without a CarPlay scene.
      setupAudioRouteChangeObserver()
      setCarAudioRouteActive(SpatialSessionManager.isCarAudioRouteActive)
      // Interruption/reset observers are installed before the first playback
      // activation, including previews, by setupAudioSessionObservers().
    }

    /// Runs before every playback activation and installs the observers once.
    func setupAudioSessionObservers() {
      guard !audioSessionObserversSetup else { return }
      Logger.audio.debug("AudioManager: Setting up audio session observers on first playback")
      setupAudioInterruptionObserver()
      setupMediaServicesResetObserver()

      // A media-services reset invalidates every node bound to the dead
      // engine. Tear down players (keeping selection) for lazy rebuild.
      AudioEngineManager.shared.onEngineReset = { [weak self] in
        for sound in self?.sounds ?? [] { sound.unload() }
      }

      audioSessionObserversSetup = true
    }

    /// The media daemon can restart at any time. Apple requires rebuilding every
    /// audio object and not resuming playback automatically.
    private func setupMediaServicesResetObserver() {
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: nil,
        queue: .main
      ) { _ in
        Logger.audio.error("AudioManager: Media services were reset")
        Task { @MainActor in
          AudioEngineManager.shared.handleMediaServicesReset()
        }
      }
    }

    private func setupTerminationObserver() {
      NotificationCenter.default.addObserver(
        forName: UIApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated { self.handleAppTermination() }
      }
    }

    private func setupBackgroundObservers() {
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.handleDidEnterBackground() }
      }

      NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.handleWillEnterForeground() }
      }
    }

    func handleDidEnterBackground() {
      Logger.audio.debug(
        "AudioManager: handleDidEnterBackground called - isGloballyPlaying: \(self.isGloballyPlaying)"
      )

      saveState()

      // Deactivate only while paused, so other apps can play.
      if !isGloballyPlaying {
        AudioSessionManager.shared.deactivate()
      }
    }

    func handleWillEnterForeground() {
      Logger.audio.debug(
        "AudioManager: handleWillEnterForeground called - isGloballyPlaying: \(self.isGloballyPlaying)"
      )

      setCarAudioRouteActive(
        SpatialSessionManager.isCarAudioRouteActive, reconfigureSession: false)
      AudioSessionManager.shared.reactivateForForeground(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isCarPlayConnected: isCarPlayConnected,
        isPlaying: isGloballyPlaying
      )

      // Reinstall media controls in case iOS disconnected them in the background.
      Task { @MainActor in
        if isGloballyPlaying {
          Logger.audio.debug("AudioManager: Refreshing media controls after foreground")
          setupMediaControls()

          let currentPreset = PresetManager.shared.currentPreset
          nowPlayingManager.updateInfo(
            preset: currentPreset,
            presetName: currentPreset?.name,
            creatorName: currentPreset?.creatorName,
            artworkId: currentPreset?.artworkId,
            isPlaying: true
          )
        }
      }
    }

    private func setupAudioInterruptionObserver() {
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        // Delivered on the main queue. The notification never leaves it.
        nonisolated(unsafe) let note = notification
        MainActor.assumeIsolated { self?.handleAudioInterruption(note) }
      }
    }

    func handleAudioInterruption(_ notification: Notification) {
      guard let userInfo = notification.userInfo,
        let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: typeValue)
      else {
        return
      }

      switch type {
      case .began:
        handleInterruptionBegan()
      case .ended:
        handleInterruptionEnded(userInfo: userInfo)
      @unknown default:
        break
      }
    }

    private func handleInterruptionBegan() {
      Logger.audio.debug("AudioManager: Audio interruption began - pausing playback")
      // The session stays active while paused, so .shouldResume can arrive when
      // nothing was playing. Record the real state.
      let shouldResume = isGloballyPlaying
      // Synchronous so the pause can't land after a new play request. Also stops
      // previews while globally paused, with no fade.
      setGlobalPlaybackState(false, pauseFadeDuration: 0)
      // Set after the pause, which clears it.
      wasPlayingWhenInterrupted = shouldResume
    }

    private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
      let wasPlaying = wasPlayingWhenInterrupted
      // Consume on every end, including missing options or a refusal to resume.
      wasPlayingWhenInterrupted = false
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        // .shouldResume is only a hint, so resume only if audio was playing.
        if options.contains(.shouldResume), wasPlaying {
          Logger.audio.debug(
            "AudioManager: Audio interruption ended with shouldResume flag - resuming playback")
          setGlobalPlaybackState(true)
        } else {
          Logger.audio.debug(
            "AudioManager: Audio interruption ended; not resuming (shouldResume: \(options.contains(.shouldResume)), wasPlaying: \(wasPlaying))"
          )
        }
      }
    }

    private func setupAudioRouteChangeObserver() {
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        // Delivered on the main queue. The notification never leaves it.
        nonisolated(unsafe) let note = notification
        MainActor.assumeIsolated { self?.handleAudioRouteChange(note) }
      }
    }

    func handleAudioRouteChange(_ notification: Notification) {
      // Every reason re-reads the route because category and configuration changes
      // can expose the car output too.
      guard let userInfo = notification.userInfo,
        let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
      else {
        return
      }

      setCarAudioRouteActive(
        SpatialSessionManager.isCarAudioRouteActive,
        reconfigureSession: reason != .oldDeviceUnavailable)

      // A car route ends any spatial session (rationale on the helper).
      if SpatialSessionManager.isCarAudioRouteActive {
        Task { @MainActor in
          SpatialSessionManager.shared.endSessionForCarAudio()
        }
      }

      switch reason {
      case .oldDeviceUnavailable:
        Logger.audio.debug("AudioManager: Audio route changed - old device unavailable")
        // Also stop a preview and cancel any pending interruption resume, even
        // if the interruption has already made global playback appear paused.
        setGlobalPlaybackState(false, pauseFadeDuration: 0)
      case .newDeviceAvailable:
        Logger.audio.debug("AudioManager: Audio route changed - new device available")
      default:
        break
      }
    }
  #endif

  #if os(macOS)
    private func setupMacOSNotificationObservers() {
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { _ in
        // willTerminate fires on the main queue, so recover isolation synchronously
        // (a Task would defer past app exit and lose the state save).
        MainActor.assumeIsolated { self.handleAppTermination() }
      }

      Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.saveState() }
      }
    }
  #endif

  func handleAppTermination() {
    Logger.audio.debug("AudioManager: App is terminating, cleaning up")
    cleanup()
  }

  func cleanup() {
    saveState()

    #if os(iOS) || os(visionOS)
      AudioSessionManager.shared.deactivate()
    #endif

    Task { @MainActor in
      nowPlayingManager.clear()
    }
    Logger.audio.debug("AudioManager: Cleanup complete")
  }
}
