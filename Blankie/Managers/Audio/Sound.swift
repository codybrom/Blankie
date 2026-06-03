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
      debugLog("🔊 Sound: \(fileName) -  isSelected set to \(isSelected)")

      // If sound was just selected, start playing it immediately when playback becomes active
      // Only do this after AudioManager is fully initialized to avoid circular dependency
      if isSelected, oldValue == false {
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }

          // Fix race condition: Ensure sound is still selected before proceeding
          guard self.isSelected else {
            debugLog("🎵 Sound: Aborting auto-play for '\(self.fileName)' - sound was deselected")
            return
          }

          // In solo mode only the soloed sound may sound; other sounds keep
          // their selection but must stay silent. Without this, a preset's
          // selected sounds auto-play alongside a restored solo sound.
          if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
            debugLog("🎵 Sound: Skipping auto-play for '\(self.fileName)' - solo mode active")
            return
          }

          // Check if playback is active, or will become active soon
          if AudioManager.shared.isGloballyPlaying {
            debugLog(
              "🎵 Sound: Auto-playing newly selected sound '\(self.fileName)' during active playback"
            )
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
                debugLog(
                  "🎵 Sound: Aborting delayed auto-play for '\(self.fileName)' - sound was deselected"
                )
                return
              }

              guard AudioManager.shared.isGloballyPlaying else { return }

              // Re-check solo here too: it may have been entered during the yield.
              if let solo = AudioManager.shared.soloModeSound, solo.id != self.id {
                debugLog(
                  "🎵 Sound: Skipping delayed auto-play for '\(self.fileName)' - solo mode active")
                return
              }

              debugLog(
                "🎵 Sound: Auto-playing newly selected sound '\(self.fileName)' after auto-start")
              self.loadSound()
              self.resetSoundPosition()  // Apply randomization if enabled
              self.play()
            }
          }
        }
      }

      // If sound was just deselected, stop playing it immediately
      if !isSelected, oldValue == true {
        debugLog("🎵 Sound: Auto-stopping newly deselected sound '\(fileName)'")
        // If player exists, pause it
        if player != nil {
          pause(immediate: true)
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

  var volumeDebounceTimer: Timer?
  var updateVolumeLogTimer: Timer?

  @Published var volume: Float = 0.75 {
    didSet {
      guard volume >= 0, volume <= 1 else {
        debugLog("❌ Sound: Invalid volume for '\(fileName)'")
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
          debugLog("🚗 Sound: Skipping volume save for '\(self.fileName)' during Quick Mix mode")
          return
        }

        UserDefaults.shared.set(self.volume, forKey: "\(self.fileName)_volume")
        debugLog("🔊 Sound: \(self.fileName) final volume saved as \(self.volume)")
      }
    }
  }

  var player: AVAudioPlayer?
  let fadeDuration: TimeInterval = 0.1
  var fadeTimer: Timer?
  var fadeStartVolume: Float = 0
  var targetVolume: Float = 1.0
  private var globalSettingsObserver: AnyCancellable?
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
      debugLog("⚠️ Sound: Already loading '\(fileName).\(fileExtension)', skipping")
      return
    }

    // If player already exists, no need to reload
    guard player == nil else {
      debugLog("🔍 Sound: Player already loaded for '\(fileName).\(fileExtension)'")
      return
    }

    isLoading = true
    defer { isLoading = false }

    debugLog("🔍 Sound: Loading '\(fileName).\(fileExtension)'")

    guard let soundURL = getSoundURL() else {
      debugLog("❌ Sound: File not found for '\(fileName).\(fileExtension)'")
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }

    do {
      // Extract metadata before creating player
      extractMetadata(from: soundURL)

      player = try AVAudioPlayer(contentsOf: soundURL)

      // Additional validation
      guard let loadedPlayer = player else {
        debugLog("❌ Sound: Player is nil after initialization for '\(fileName)'")
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

      debugLog(
        "🔊 Sound: Loaded sound '\(fileName).\(fileExtension)' with volume: \(loadedPlayer.volume)")
    } catch {
      debugLog("❌ Sound: Failed to load '\(fileName).\(fileExtension)': \(error)")
      debugLog(
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
    debugLog("🔄 Sound: Deinitialized '\(fileName)'")
    globalSettingsObserver?.cancel()
    customizationObserver?.cancel()
    fadeTimer?.invalidate()
    volumeDebounceTimer?.invalidate()
    updateVolumeLogTimer?.invalidate()
  }

  // MARK: - AVAudioPlayerDelegate

  public func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
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
        debugLog("🔊 Sound: Non-looping sound '\(self.fileName)' finished playing")

        // Check if we're in solo mode with this sound
        if AudioManager.shared.soloModeSound?.id == self.id {
          debugLog("🔊 Sound: Non-looping sound in solo mode finished, pausing global playback")
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
