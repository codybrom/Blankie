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
      // Delay audio session observers until first playback to avoid interrupting other apps
      // setupAudioInterruptionObserver()
      // setupAudioRouteChangeObserver()
    }

    // Call this when we first start playing to setup audio session observers
    func setupAudioSessionObservers() {
      guard !audioSessionObserversSetup else { return }
      Logger.audio.debug("AudioManager: Setting up audio session observers on first playback")
      setupAudioInterruptionObserver()
      setupAudioRouteChangeObserver()
      setupMediaServicesResetObserver()

      // A media-services reset invalidates every node bound to the dead
      // engine; tear down players (keeping selection) for lazy rebuild.
      AudioEngineManager.shared.onEngineReset = { [weak self] in
        self?.sounds.forEach { $0.unload() }
      }

      audioSessionObserversSetup = true
    }

    /// The media daemon can restart out from under us; Apple requires
    /// rebuilding all audio objects and never auto-resuming playback.
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
        self.handleAppTermination()
      }
    }

    private func setupBackgroundObservers() {
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handleDidEnterBackground()
      }

      NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handleWillEnterForeground()
      }
    }

    func handleDidEnterBackground() {
      Logger.audio.debug(
        "AudioManager: handleDidEnterBackground called - isGloballyPlaying: \(self.isGloballyPlaying)"
      )

      saveState()

      // Only deactivate audio session if we're not playing
      // This allows other apps to play when Blankie is paused in background
      if !isGloballyPlaying {
        AudioSessionManager.shared.deactivate()
      }
    }

    func handleWillEnterForeground() {
      Logger.audio.debug(
        "AudioManager: handleWillEnterForeground called - isGloballyPlaying: \(self.isGloballyPlaying)"
      )

      AudioSessionManager.shared.reactivateForForeground(
        mixWithOthers: GlobalSettings.shared.mixWithOthers,
        isPlaying: isGloballyPlaying
      )

      // Refresh media controls to ensure iOS hasn't disconnected them
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
        self?.handleAudioInterruption(notification)
      }
    }

    private func handleAudioInterruption(_ notification: Notification) {
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
      if isGloballyPlaying {
        Task { @MainActor in
          // Update Now Playing info to show paused state with current position
          // Use active (selected) sounds to ensure we have position even when pausing
          let activeSounds = self.sounds.filter { $0.isSelected }
          if let longestSound = activeSounds.max(by: {
            $0.playbackDuration < $1.playbackDuration
          }), longestSound.isLoaded {
            self.nowPlayingManager.updateProgress(
              currentTime: longestSound.playbackPosition,
              duration: longestSound.playbackDuration
            )
          }

          self.setGlobalPlaybackState(false)
        }
      }
    }

    private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
          Logger.audio.debug(
            "AudioManager: Audio interruption ended with shouldResume flag - resuming playback")
          Task { @MainActor in
            self.setGlobalPlaybackState(true)
          }
        } else {
          Logger.audio.debug("AudioManager: Audio interruption ended without shouldResume flag")
        }
      }
    }

    private func setupAudioRouteChangeObserver() {
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioRouteChange(notification)
      }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
      guard let userInfo = notification.userInfo,
        let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
      else {
        return
      }

      switch reason {
      case .oldDeviceUnavailable:
        Logger.audio.debug("AudioManager: Audio route changed - old device unavailable")
        if isGloballyPlaying {
          Task { @MainActor in
            self.setGlobalPlaybackState(false)
          }
        }
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
        self.handleAppTermination()
      }

      Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.saveState()
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
      // Deactivate audio session on cleanup/termination
      AudioSessionManager.shared.deactivate()
    #endif

    Task { @MainActor in
      nowPlayingManager.clear()
    }
    Logger.audio.debug("AudioManager: Cleanup complete")
  }
}
