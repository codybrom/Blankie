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

/// Represents a single sound with its associated properties and playback controls.
open class Sound: NSObject, ObservableObject, Identifiable, AVAudioPlayerDelegate {

  public let id = UUID()
  let originalTitle: String
  let originalSystemIconName: String
  let fileName: String
  let fileExtension: String
  let lufs: Float?
  let normalizationFactor: Float?
  let truePeakdBTP: Float?
  let needsLimiter: Bool

  // Properties for unified sound model
  let isCustom: Bool
  let fileURL: URL?
  let dateAdded: Date?
  let customSoundDataID: UUID?  // For linking to SwiftData if needed

  // Computed properties that respect customizations
  var title: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveTitle(
      originalTitle: originalTitle) ?? originalTitle
  }

  var systemIconName: String {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveIconName(
      originalIconName: originalSystemIconName) ?? originalSystemIconName
  }

  var customColor: Color? {
    return SoundCustomizationManager.shared.getCustomization(for: fileName)?.effectiveColor
  }

  @Published var isSelected = false {
    didSet {
      UserDefaults.standard.set(isSelected, forKey: "\(fileName)_isSelected")
      print("🔊 Sound: \(fileName) -  isSelected set to \(isSelected)")

      // If sound was just selected, start playing it immediately when playback becomes active
      // Only do this after AudioManager is fully initialized to avoid circular dependency
      if isSelected && oldValue == false {
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }

          // Check if playback is active, or will become active soon
          if AudioManager.shared.isGloballyPlaying {
            print(
              "🎵 Sound: Auto-playing newly selected sound '\(self.fileName)' during active playback"
            )
            self.loadSound()
            self.resetSoundPosition()  // Apply randomization if enabled
            self.play()
          } else {
            // If playback isn't active yet, wait for auto-start to kick in
            Task { @MainActor [weak self] in
              await Task.yield()  // Allow auto-start to process
              guard let self = self,
                AudioManager.shared.isGloballyPlaying
              else { return }
              print(
                "🎵 Sound: Auto-playing newly selected sound '\(self.fileName)' after auto-start")
              self.loadSound()
              self.resetSoundPosition()  // Apply randomization if enabled
              self.play()
            }
          }
        }
      }

      // If sound was just deselected, stop playing it immediately
      if !isSelected && oldValue == true {
        print("🎵 Sound: Auto-stopping newly deselected sound '\(self.fileName)'")
        // If player exists, pause it
        if self.player != nil {
          self.pause(immediate: true)
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

  internal var volumeDebounceTimer: Timer?
  internal var updateVolumeLogTimer: Timer?

  @Published var volume: Float = 0.75 {
    didSet {
      guard volume >= 0 && volume <= 1 else {
        print("❌ Sound: Invalid volume for '\(fileName)'")
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
          print("🚗 Sound: Skipping volume save for '\(self.fileName)' during Quick Mix mode")
          return
        }

        UserDefaults.standard.set(self.volume, forKey: "\(self.fileName)_volume")
        print("🔊 Sound: \(self.fileName) final volume saved as \(self.volume)")
      }
    }
  }

  var player: AVAudioPlayer?
  internal let fadeDuration: TimeInterval = 0.1
  internal var fadeTimer: Timer?
  internal var fadeStartVolume: Float = 0
  internal var targetVolume: Float = 1.0
  private var globalSettingsObserver: AnyCancellable?
  private var customizationObserver: AnyCancellable?
  internal var isResetting = false
  private var isLoading = false

  // Metadata properties
  @Published var channelCount: Int?
  @Published var duration: TimeInterval?
  @Published var fileSize: Int64?
  @Published var fileFormat: String?

  // Playback progress tracking
  @Published var playbackProgress: Double = 0.0
  internal var progressTimer: Timer?

  init(
    title: String, systemIconName: String, fileName: String, fileExtension: String = "mp3",
    defaultOrder: Int = 0, lufs: Float? = nil, normalizationFactor: Float? = nil,
    truePeakdBTP: Float? = nil, needsLimiter: Bool = false,
    isCustom: Bool = false, fileURL: URL? = nil, dateAdded: Date? = nil,
    customSoundDataID: UUID? = nil
  ) {
    self.originalTitle = title
    self.originalSystemIconName = systemIconName
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

    super.init()

    // Restore saved volume
    self.volume = UserDefaults.standard.float(forKey: "\(fileName)_volume")
    if self.volume == 0 {
      self.volume = 0.75
    }

    // Restore selected state
    self.isSelected = UserDefaults.standard.bool(forKey: "\(fileName)_isSelected")

    // Observe "All Sounds" volume changes
    globalSettingsObserver = GlobalSettings.shared.$volume
      .sink { [weak self] _ in
        self?.updateVolume()
      }

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
      print("⚠️ Sound: Already loading '\(fileName).\(fileExtension)', skipping")
      return
    }

    // If player already exists, no need to reload
    guard player == nil else {
      print("🔍 Sound: Player already loaded for '\(fileName).\(fileExtension)'")
      return
    }

    isLoading = true
    defer { isLoading = false }

    print("🔍 Sound: Loading '\(fileName).\(fileExtension)'")

    guard let soundURL = getSoundURL() else {
      print("❌ Sound: File not found for '\(fileName).\(fileExtension)'")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      // Extract metadata before creating player
      extractMetadata(from: soundURL)

      player = try AVAudioPlayer(contentsOf: soundURL)

      // Additional validation
      guard let loadedPlayer = player else {
        print("❌ Sound: Player is nil after initialization for '\(fileName)'")
        return
      }

      // Configure player settings
      configurePlayer(loadedPlayer)

      // Validate player state
      _ = validatePlayer(loadedPlayer)

      // Set initial volume with normalization
      updateVolume()

      // Apply random start position if enabled
      applyRandomStartPosition(to: loadedPlayer)

      print(
        "🔊 Sound: Loaded sound '\(fileName).\(fileExtension)' with volume: \(loadedPlayer.volume)")
    } catch {
      print("❌ Sound: Failed to load '\(fileName).\(fileExtension)': \(error)")
      print(
        "❌ Sound: Error details - domain: \((error as NSError).domain), code: \((error as NSError).code)"
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
    print("🔄 Sound: Deinitialized '\(fileName)'")
    globalSettingsObserver?.cancel()
    customizationObserver?.cancel()
    fadeTimer?.invalidate()
    volumeDebounceTimer?.invalidate()
    updateVolumeLogTimer?.invalidate()
    progressTimer?.invalidate()
  }

  // MARK: - AVAudioPlayerDelegate

  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard flag else { return }

    // Check if sound should loop
    let shouldLoop: Bool
    if let customization = SoundCustomizationManager.shared.getCustomization(for: fileName) {
      shouldLoop = customization.loopSound ?? true
    } else {
      shouldLoop = true  // Default to true for all sounds
    }

    // If not looping, handle completion
    if !shouldLoop {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        print("🔊 Sound: Non-looping sound '\(self.fileName)' finished playing")

        // Check if we're in solo mode with this sound
        if AudioManager.shared.soloModeSound?.id == self.id {
          print("🔊 Sound: Non-looping sound in solo mode finished, pausing global playback")
          // Reset the sound position for next play
          self.resetSoundPosition()
          // Pause global playback but stay in solo mode
          AudioManager.shared.setGlobalPlaybackState(false)
        } else {
          // Normal mode - deselect the sound
          self.isSelected = false
        }
      }
    }
  }
}
