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
  private var cancellables = Set<AnyCancellable>()
  static let shared = AudioManager()
  var onReset: (() -> Void)?

  @Published var sounds: [Sound] = []
  @Published private(set) var isGloballyPlaying: Bool = false

  private var modelContext: ModelContext?
  private let commandCenter = MPRemoteCommandCenter.shared()
  private var nowPlayingInfo: [String: Any] = [:]
  @MainActor private var isInitializing = true
  private var customSoundObserver: AnyCancellable?

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
    Task { @MainActor [weak self] in
      guard let self = self else { return }

      guard !self.isInitializing || forceUpdate else {
        print("🎵 AudioManager: Ignoring setPlaybackState during initialization")
        return
      }

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
    print("🎵 AudioManager: Loading built-in sounds from JSON")

    // Start with an empty array
    self.sounds = []

    // Load built-in sounds
    loadBuiltInSounds()

    // Load custom sounds if available
    if modelContext != nil {
      loadCustomSounds()
    }
  }

  private func loadBuiltInSounds() {
    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json") else {
      print("❌ AudioManager: sounds.json file not found in Resources folder")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let soundsContainer = try decoder.decode(SoundsContainer.self, from: data)

      let builtInSounds = soundsContainer.sounds
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

      // Add built-in sounds to the sounds array
      self.sounds.append(contentsOf: builtInSounds)
      print("🎵 AudioManager: Loaded \(builtInSounds.count) built-in sounds")
    } catch {
      print("❌ AudioManager: Failed to parse sounds.json: \(error)")
      ErrorReporter.shared.report(error)
    }
  }

  private func loadCustomSounds() {
    print("🎵 AudioManager: Loading custom sounds")

    // Get all custom sounds from the database
    let customSoundData = CustomSoundManager.shared.getAllCustomSounds()

    // Remove any existing custom sounds from the array
    sounds.removeAll(where: { $0 is CustomSound })

    // Create Sound objects for each custom sound
    let customSounds = customSoundData.compactMap { data -> CustomSound? in
      guard let url = CustomSoundManager.shared.getURLForCustomSound(data) else {
        print("❌ AudioManager: Could not get URL for custom sound \(data.fileName)")
        return nil
      }

      return CustomSound(
        title: data.title,
        systemIconName: data.systemIconName,
        fileName: data.fileName,
        fileExtension: data.fileExtension,
        fileURL: url,
        customSoundData: data
      )
    }

    // Add custom sounds to the array
    sounds.append(contentsOf: customSounds)
    print("🎵 AudioManager: Loaded \(customSounds.count) custom sounds")

    // Re-setup observers for the new sounds
    setupSoundObservers()
  }

  #if os(iOS) || os(visionOS)
    private func setupAudioSessionForPlayback() {
      do {
        // Force exclusive audio when CarPlay is connected
        #if CARPLAY_ENABLED
          let isCarPlayConnected = CarPlayInterface.shared.isConnected
        #else
          let isCarPlayConnected = false
        #endif

        // Only setup audio session when we actually start playing
        if GlobalSettings.shared.mixWithOthers && !isCarPlayConnected {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers, .duckOthers]
          )
        } else {
          try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []  // Exclusive playback
          )
        }
        try AVAudioSession.sharedInstance().setActive(true)
        print(
          "🎵 AudioManager: Audio session activated for playback (mixWithOthers: \(GlobalSettings.shared.mixWithOthers && !isCarPlayConnected), CarPlay: \(isCarPlayConnected))"
        )
      } catch {
        print("❌ AudioManager: Failed to setup audio session: \(error)")
      }
    }
  #endif

  private func setupMediaControls() {
    print("🎵 AudioManager: Setting up media controls")

    // Enable the commands
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true

    // Remove all previous handlers
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)

    // Add handlers
    commandCenter.playCommand.addTarget { [weak self] _ in
      print("🎵 AudioManager: Media key play command received")
      Task { @MainActor in
        // Only play if we're currently paused
        if !(self?.isGloballyPlaying ?? false) {
          self?.setGlobalPlaybackState(true)
        }
      }
      return .success
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      print("🎵 AudioManager: Media key pause command received")
      Task { @MainActor in
        // Only pause if we're currently playing
        if self?.isGloballyPlaying ?? false {
          self?.setGlobalPlaybackState(false)
        }
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

    #if os(iOS) || os(visionOS)
      // Setup audio session when starting playback
      setupAudioSessionForPlayback()
    #endif

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
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0  // Start as paused

    #if os(iOS) || os(visionOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = UIImage(data: imageData)
      {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      }
    #elseif os(macOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = NSImage(data: imageData)
      {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      }
    #endif

    updatePlaybackState()
  }

  public func updateNowPlayingInfoForPreset(presetName: String? = nil) {
    updateNowPlayingInfo(presetName: presetName)
  }

  private func updateNowPlayingInfo(presetName: String? = nil) {
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

    #if os(iOS) || os(visionOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = UIImage(data: imageData)
      {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      }
    #elseif os(macOS)
      if let imageUrl = Bundle.main.url(forResource: "NowPlaying", withExtension: "png"),
        let imageData = try? Data(contentsOf: imageUrl),
        let image = NSImage(data: imageData)
      {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
          return image
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
      }
    #endif

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func updateNowPlayingState() {
    let playbackRate: Double = isGloballyPlaying ? 1.0 : 0.0
    print(
      "🎵 AudioManager: Updating now playing state to \(isGloballyPlaying), playbackRate: \(playbackRate)"
    )

    // Update the playback state in Now Playing
    updatePlaybackState()
  }

  private func updatePlaybackState() {
    // Ensure nowPlayingInfo dictionary exists
    if nowPlayingInfo.isEmpty {
      // Recreate basic info if needed
      nowPlayingInfo[MPMediaItemPropertyTitle] = "Ambient Sounds"
      nowPlayingInfo[MPMediaItemPropertyArtist] = "Blankie"
    }

    // Update playback state
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isGloballyPlaying ? 1.0 : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0  // Infinite for ambient sounds

    // Update the now playing info
    print(
      "🎵 AudioManager: Updating now playing state to \(isGloballyPlaying), playbackRate: \(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1)"
    )
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func setupNotificationObservers() {
    #if os(iOS) || os(visionOS)
      setupIOSNotificationObservers()
    #elseif os(macOS)
      setupMacOSNotificationObservers()
    #endif
  }

  #if os(iOS) || os(visionOS)
  private func setupIOSNotificationObservers() {
    setupTerminationObserver()
    setupCarPlayObserver()
    setupBackgroundObservers()
    setupAudioInterruptionObserver()
    setupAudioRouteChangeObserver()
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

  private func setupCarPlayObserver() {
    #if CARPLAY_ENABLED
      NotificationCenter.default.addObserver(
        forName: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        queue: .main
      ) { [weak self] notification in
        if let isConnected = notification.userInfo?["isConnected"] as? Bool {
          print("🎵 AudioManager: CarPlay connection changed to: \(isConnected)")
          if self?.isGloballyPlaying == true {
            self?.setupAudioSessionForPlayback()
          }
        }
      }
    #endif
  }

  private func setupBackgroundObservers() {
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.saveState()
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.handleWillEnterForeground()
    }
  }

  private func handleWillEnterForeground() {
    do {
      if GlobalSettings.shared.mixWithOthers {
        try AVAudioSession.sharedInstance().setCategory(
          .playback,
          mode: .default,
          options: [.mixWithOthers, .duckOthers]
        )
      } else {
        try AVAudioSession.sharedInstance().setCategory(
          .playback,
          mode: .default,
          options: []
        )
      }
      try AVAudioSession.sharedInstance().setActive(true)

      if isGloballyPlaying {
        updateNowPlayingInfo()
      }
    } catch {
      print("Failed to reactivate audio session: \(error)")
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
    print("🎵 AudioManager: Audio interruption began - pausing playback")
    if isGloballyPlaying {
      Task { @MainActor in
        self.setGlobalPlaybackState(false)
      }
    }
  }

  private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        print("🎵 AudioManager: Audio interruption ended with shouldResume flag")
        if !GlobalSettings.shared.mixWithOthers {
          print("🎵 AudioManager: Not resuming automatically in exclusive mode")
        }
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
      print("🎵 AudioManager: Audio route changed - old device unavailable")
      if isGloballyPlaying {
        isGloballyPlaying = false
        updatePlaybackState()
      }
    case .newDeviceAvailable:
      print("🎵 AudioManager: Audio route changed - new device available")
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

  private func handleAppTermination() {
    print("🎵 AudioManager: App is terminating, cleaning up")
    cleanup()
  }

  private func cleanup() {
    saveState()
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

    #if os(iOS) || os(visionOS)
      // Deactivate audio session when stopping to allow other apps to play
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("🎵 AudioManager: Audio session deactivated")
      } catch {
        print("❌ AudioManager: Failed to deactivate audio session: \(error)")
      }
    #endif

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
    setGlobalPlaybackState(false)
    // Reset all sounds
    sounds.forEach { sound in
      sound.volume = 1.0
      sound.isSelected = false
    }
    // Reset "All Sounds" volume
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

  // MARK: - SwiftData Integration

  /// Set up the model context for accessing custom sounds
  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    CustomSoundManager.shared.setModelContext(context)
    setupCustomSoundObservers()
    loadCustomSounds()
  }

  private func setupCustomSoundObservers() {
    // Observe custom sound changes
    customSoundObserver = NotificationCenter.default.publisher(for: .customSoundAdded)
      .merge(with: NotificationCenter.default.publisher(for: .customSoundDeleted))
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.loadCustomSounds()
        }
      }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    cleanup()
    print("🎵 AudioManager: Deinit called, cleanup performed")
  }
}
