//
//  AudioManager.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

class AudioManager: ObservableObject {
  private var cancellables = Set<AnyCancellable>()
  static let shared = AudioManager()
  var onReset: (() -> Void)?

  @Published var sounds: [Sound] = []
  @Published private(set) var isGloballyPlaying: Bool = false

  private let commandCenter = MPRemoteCommandCenter.shared()
  private var nowPlayingInfo: [String: Any] = [:]
  private var isInitializing = true

  private init() {
    print("🎵 AudioManager: Initializing")
    loadSounds()
    loadSavedState()
    setupNowPlaying()
    setupMediaControls()
    setupNotificationObservers()
    setupSoundObservers()

    // Handle autoplay behavior after a slight delay to ensure proper initialization
    Task { @MainActor in
      // Short delay to allow everything to initialize
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

      self.isInitializing = false

      if !GlobalSettings.shared.alwaysStartPaused {
        let hasSelectedSounds = self.sounds.contains { $0.isSelected }
        if hasSelectedSounds {
          // Set initial state
          self.isGloballyPlaying = true

          // Start playback
          self.playSelected()

          // Update Now Playing info with preset name
          if let currentPreset = PresetManager.shared.currentPreset {
            self.updateNowPlayingInfo(presetName: currentPreset.name)
          } else {
            self.updateNowPlayingInfo()
          }
        }
      } else {
        // Ensure we're in a paused state
        self.isGloballyPlaying = false
        self.updateNowPlayingInfo()
      }
    }
  }

  private func setupSoundObservers() {
    // Clear any existing observers
    cancellables.removeAll()
    // Set up new observers for each sound
    for sound in sounds {
      sound.objectWillChange
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          guard self != nil else { return }
          Task { @MainActor in
            PresetManager.shared.updateCurrentPresetState()
          }
        }
        .store(in: &cancellables)
    }
  }
  func setPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    guard !isInitializing || forceUpdate else {
      print("🎵 AudioManager: Ignoring setPlaybackState during initialization")
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      if self.isGloballyPlaying != playing {
        print(
          "🎵 AudioManager: Setting playback state to \(playing) - Current global state: \(self.isGloballyPlaying)"
        )
        self.isGloballyPlaying = playing

        if playing {
          self.playSelected()
        } else {
          self.pauseAll()
        }
        self.updateNowPlayingInfo()
      } else {
        print("🎵 AudioManager: setPlaybackState called, but state is the same \(playing), ignoring")
      }
    }
  }
  private func loadSounds() {
    print("🎵 AudioManager: Loading sounds from JSON")
    let bundlePath = Bundle.main.bundlePath
    print("📦 Bundle path: \(bundlePath)")

    if let resourcePath = Bundle.main.resourcePath {
      print("📂 Resource path: \(resourcePath)")
      do {
        let resources = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
        print("📑 Resources in bundle: \(resources)")
      } catch {
        print("❌ Error listing resources: \(error)")
      }
    }

    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json") else {
      print("❌ AudioManager: sounds.json file not found in Resources folder")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let soundsContainer = try decoder.decode(SoundsContainer.self, from: data)

      self.sounds = soundsContainer.sounds
        .sorted(by: { $0.defaultOrder < $1.defaultOrder })
        .map { soundData in
          let supportedExtensions = ["wav", "m4a", "mp3", "aiff"]
          let fileExtension =
            supportedExtensions.first { soundData.fileName.hasSuffix(".\($0)") } ?? "mp3"
          let cleanedFileName = soundData.fileName.replacingOccurrences(
            of: ".\(fileExtension)", with: "")

          return Sound(
            title: soundData.title,
            systemIconName: soundData.systemIconName,
            fileName: cleanedFileName,
            fileExtension: fileExtension
          )
        }
    } catch {
      print("❌ AudioManager: Failed to parse sounds.json: \(error)")
      ErrorReporter.shared.report(error)
    }
  }

  private func setupMediaControls() {
    print("🎵 AudioManager: Setting up media controls")
    // Remove all previous handlers
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)

    // Add handlers
    commandCenter.playCommand.addTarget { [weak self] _ in
      print("🎵 AudioManager: Media key play command received")
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      print("🎵 AudioManager: Media key pause command received")
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      print("🎵 AudioManager: Media key toggle command received")
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }
  }

  // Update playSelected to check global state
  private func playSelected() {
    print("🎵 AudioManager: Playing selected sounds")
    guard isGloballyPlaying else {
      print("🎵 AudioManager: Not playing sounds because global playback is disabled")
      return
    }

    for sound in sounds where sound.isSelected {
      print("  - Playing '\(sound.fileName)'")
      sound.play()
    }

    // Update Now Playing info with current preset name
    if let currentPreset = PresetManager.shared.currentPreset {
      self.updateNowPlayingInfo(presetName: currentPreset.name)
    } else {
      self.updateNowPlayingInfo()
    }
  }

  private func loadSavedState() {
    guard let state = UserDefaults.standard.array(forKey: "soundState") as? [[String: Any]] else {
      return
    }
    for savedState in state {
      guard let fileName = savedState["fileName"] as? String,
        let sound = sounds.first(where: { $0.fileName == fileName })
      else {
        continue
      }
      sound.isSelected = savedState["isSelected"] as? Bool ?? false
      sound.volume = savedState["volume"] as? Float ?? 1.0
    }
  }

  private func setupNowPlaying() {
    print("🎵 AudioManager: Setting up Now Playing info")
    nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"

    if let url = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
      let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
        NSImage(cgImage: cgImage, size: size)
      }
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
    updatePlaybackState()
  }

  public func updateNowPlayingInfo(presetName: String? = nil) {
    var nowPlayingInfo = [String: Any]()

    // Get the current preset name for the title
    let displayTitle: String
    if let name = presetName {
      // Only use preset name if it's not "Default" or doesn't start with "Preset "
      if name != "Default" && !name.starts(with: "Preset ") {
        displayTitle = name
      } else {
        displayTitle = "Ambient Sounds"
      }
    } else {
      displayTitle = "Ambient Sounds"
    }

    print("🎵 AudioManager: Updating Now Playing info with title: \(displayTitle)")

    nowPlayingInfo[MPMediaItemPropertyTitle] = displayTitle
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isGloballyPlaying ? 1.0 : 0.0

    if let url = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
      let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
        NSImage(cgImage: cgImage, size: size)
      }
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func updateNowPlayingState() async {
    let playbackRate: Double = isGloballyPlaying ? 1.0 : 0.0
    print(
      "🎵 AudioManager: Updating now playing state to \(isGloballyPlaying), playbackRate: \(playbackRate)"
    )

    // Update volume through GlobalSettings
    await GlobalSettings.shared.setVolume(isGloballyPlaying ? 1.0 : 0.0)
  }

  private func updatePlaybackState() {
    // Update playback state
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isGloballyPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0  // Infinite for ambient sounds
    // Update the now playing info
    print(
      "🎵 AudioManager: Updating now playing state to \(isGloballyPlaying), "
        + "playbackRate: \(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func setupNotificationObservers() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.handleAppTermination()
    }
  }
  private func handleAppTermination() {
    print("🎵 AudioManager: App is terminating, cleaning up")
    cleanup()
  }

  private func cleanup() {
    pauseAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    print("🎵 AudioManager: Cleanup complete")
  }
  func pauseAll() {
    print("🎵 AudioManager: Pausing all sounds")
    print("  - Current global play state: \(isGloballyPlaying)")

    sounds.forEach { sound in
      if sound.isSelected {
        print("  - Pausing '\(sound.fileName)'")
        sound.pause()
      }
    }
    print("🎵 AudioManager: Pause all complete")
  }
  func saveState() {
    let state = sounds.map { sound in
      [
        "id": sound.id.uuidString,
        "fileName": sound.fileName,
        "isSelected": sound.isSelected,
        "volume": sound.volume,
      ]
    }
    UserDefaults.standard.set(state, forKey: "soundState")
  }
  /// Toggles the playback state of all selected sounds
  @MainActor func togglePlayback() {
    print("🎵 AudioManager: Toggling playback")
    print("  - Current state (pre-toggle): \(isGloballyPlaying)")
    setGlobalPlaybackState(!isGloballyPlaying)
    print("  - New state (post-toggle): \(isGloballyPlaying)")
  }

  @MainActor
  func resetSounds() {
    print("🎵 AudioManager: Resetting all sounds")

    // First pause all sounds immediately
    sounds.forEach { sound in
      print("  - Stopping '\(sound.fileName)'")
      sound.pause(immediate: true)
    }
    setPlaybackState(false)
    // Reset all sounds
    sounds.forEach { sound in
      sound.volume = 1.0
      sound.isSelected = false
    }
    // Reset global volume
    GlobalSettings.shared.setVolume(1.0)

    // Call the reset callback
    onReset?()
    print("🎵 AudioManager: Reset complete")
  }

  // Public method for changing playback state
  @MainActor
  public func setGlobalPlaybackState(_ playing: Bool, forceUpdate: Bool = false) {
    guard !isInitializing || forceUpdate else {
      print("🎵 AudioManager: Ignoring setPlaybackState during initialization")
      return
    }

    print(
      "🎵 AudioManager: Setting playback state to \(playing) - Current global state: \(self.isGloballyPlaying)"
    )

    // Update state first
    self.isGloballyPlaying = playing

    // Then handle playback
    if playing {
      self.playSelected()
    } else {
      self.pauseAll()
    }

    // Always update Now Playing info with current preset name
    if let currentPreset = PresetManager.shared.currentPreset {
      self.updateNowPlayingInfo(presetName: currentPreset.name)
    } else {
      self.updateNowPlayingInfo()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    cleanup()
    print("🎵 AudioManager: Deinit called, cleanup performed")
  }
}
