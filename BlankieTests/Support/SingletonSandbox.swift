//
//  SingletonSandbox.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Isolates a test from the shared managers: mixer sounds and modes, presets, persisted preset
//  keys and (on request) in-memory stores. `restore()` puts it back and removes tracked files.
//

import AVFoundation
import Foundation
import SwiftData

@testable import Blankie

@MainActor final class SingletonSandbox {
  enum SandboxError: Error {
    case noCustomSoundsDirectory
  }

  let audioManager = AudioManager.shared
  let presetManager = PresetManager.shared

  private let originalSounds: [Sound]
  private let originalDefaultSoundOrder: [String]
  private let originalPresets: [Preset]
  private let originalCurrentPreset: Preset?
  private let originalStatesApplied: Bool
  private let originalSingle: Sound?
  private let originalPreview: Sound?
  private let originalQuickMix: Bool
  private let originalQuickMixStates: [AudioManager.QuickMixState]
  private let originalPreQuickMixPreset: Preset?
  private let originalUnsavedMix: UnsavedMix?
  private let originalPreUnsavedMixPreset: Preset?
  private let originalContext: ModelContext?
  private let defaults: DefaultsSnapshot
  private let soundNames: [String]
  private var customSoundNames: [String] = []
  private var containers: [ModelContainer] = []

  /// Joins the launch bootstrap and lets its preset apply land before taking the
  /// snapshot, so a still-running launch can't write into the test.
  static func make(soundNames: [String] = []) async -> SingletonSandbox {
    await AudioManager.shared.loadCustomSoundsWhenReady()
    try? await Task.sleep(for: .milliseconds(250))
    return SingletonSandbox(soundNames: soundNames)
  }

  private init(soundNames: [String]) {
    self.soundNames = soundNames
    originalSounds = audioManager.sounds
    originalDefaultSoundOrder = audioManager.defaultSoundOrder
    originalPresets = presetManager.presets
    originalCurrentPreset = presetManager.currentPreset
    originalStatesApplied = presetManager.presetStatesApplied
    originalSingle = audioManager.singleSound
    originalPreview = audioManager.previewModeSound
    originalQuickMix = audioManager.isQuickMix
    originalQuickMixStates = audioManager.quickMixOriginalStates
    originalPreQuickMixPreset = audioManager.preQuickMixPreset
    originalUnsavedMix = audioManager.unsavedMix
    originalPreUnsavedMixPreset = audioManager.preUnsavedMixPreset
    originalContext = audioManager.modelContext
    defaults = DefaultsSnapshot([
      PresetStorage.defaultPresetKey,
      PresetStorage.customPresetsKey,
      PresetStorage.lastActivePresetIDKey,
      PresetStorage.defaultPresetBackupKey,
      PresetStorage.customPresetsBackupKey,
      UserDefaultsKeys.singleSoundFileName,
      UserDefaultsKeys.starredItems,
      UserDefaultsKeys.quickMixSoundFileNames,
      "defaultSoundOrder",
    ])

    // Nothing may start audio, so autoplay is off and nothing plays globally.
    GlobalSettings.shared.setAutoPlayOnLaunch(false)
    if audioManager.isGloballyPlaying {
      audioManager.setGlobalPlaybackState(false)
    }
    audioManager.singleSound = nil
    audioManager.previewModeSound = nil
    audioManager.isQuickMix = false
    audioManager.unsavedMix = nil
    audioManager.preUnsavedMixPreset = nil
    // Tests install their own presets. Starting empty keeps the user's out of
    // reach of cleanup and save paths.
    presetManager.setPresets([])
    presetManager.setCurrentPreset(nil)
  }

  /// Lets queued main-actor work land, such as the 100 ms sound-change
  /// coalescing, preset-apply tasks, and notification hops.
  func settle(milliseconds: Int = 250) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
  }

  /// Polls until `condition` holds or `timeout` passes, so a check doesn't race
  /// the coalesced refresh on a busy machine the way a fixed `settle()` can.
  func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  /// Waits for a preset application's async apply (and its follow-up refresh).
  func waitForPresetApply() async {
    for _ in 0..<40 where !presetManager.presetStatesApplied {
      try? await Task.sleep(for: .milliseconds(50))
    }
    await settle()
  }

  /// Points the custom-sound and preset-artwork managers at a fresh in-memory
  /// store, so the test never reads or writes the user's rows.
  func installInMemoryStore() throws -> ModelContext {
    let container = try ModelContainer(
      for: CustomSoundData.self, PresetArtwork.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    let context = ModelContext(container)
    CustomSoundManager.shared.setModelContext(context)
    PresetArtworkManager.shared.setModelContext(context)
    return context
  }

  /// The app's real custom-sounds directory (custom-sound code reads no other).
  /// Register every name written there with `trackCustomSound(named:)`.
  func customSoundsDirectory() throws -> URL {
    guard let dir = CustomSoundManager.shared.getCustomSoundsDirectoryURL() else {
      throw SandboxError.noCustomSoundsDirectory
    }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// `restore()` removes every custom-sounds entry starting with `name`, plus its
  /// playback profile, customization, and per-sound preferences.
  func trackCustomSound(named name: String) {
    customSoundNames.append(name)
  }

  func restore() {
    audioManager.singleSound = originalSingle
    audioManager.previewModeSound = originalPreview
    audioManager.isQuickMix = originalQuickMix
    audioManager.quickMixOriginalStates = originalQuickMixStates
    audioManager.preQuickMixPreset = originalPreQuickMixPreset
    audioManager.unsavedMix = originalUnsavedMix
    audioManager.pendingLeave = nil
    audioManager.preUnsavedMixPreset = originalPreUnsavedMixPreset
    audioManager.sounds = originalSounds
    audioManager.defaultSoundOrder = originalDefaultSoundOrder
    presetManager.setPresets(originalPresets)
    presetManager.setCurrentPreset(originalCurrentPreset)
    presetManager.presetStatesApplied = originalStatesApplied
    if let originalContext {
      CustomSoundManager.shared.setModelContext(originalContext)
      PresetArtworkManager.shared.setModelContext(originalContext)
    }
    defaults.restore()

    for name in soundNames + customSoundNames {
      UserDefaults.shared.removeObject(forKey: "\(name)_isSelected")
      UserDefaults.shared.removeObject(forKey: "\(name)_volume")
    }
    for name in customSoundNames {
      PlaybackProfileStore.shared.removeProfile(for: name)
      SoundCustomizationManager.shared.removeCustomization(for: name)
    }
    if let dir = CustomSoundManager.shared.getCustomSoundsDirectoryURL(),
      let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
    {
      for entry in entries where customSoundNames.contains(where: { entry.hasPrefix($0) }) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry))
      }
    }
  }
}

/// Real audio files for tests that import, convert, or analyze them.
enum TestAudio {
  /// Writes a 16-bit PCM sine tone. The container follows the extension (.wav, .caf).
  static func writeTone(
    to url: URL, seconds: Double = 2, frequency: Double = 440, sampleRate: Double = 44_100
  ) throws {
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let frames = AVAudioFrameCount(seconds * sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
      let channels = buffer.floatChannelData
    else { throw CocoaError(.fileWriteUnknown) }
    buffer.frameLength = frames
    for frame in 0..<Int(frames) {
      let sample = Float(0.25 * sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
      for channel in 0..<Int(file.processingFormat.channelCount) {
        channels[channel][frame] = sample
      }
    }
    try file.write(from: buffer)
  }
}
