//
//  SoundCustomization.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import Foundation
import Observation
import SwiftUI
import os

/// Represents customizations applied to built-in sounds
nonisolated struct SoundCustomization: Codable, Identifiable, Sendable {
  let id: UUID
  let fileName: String
  var customTitle: String?
  var customIconName: String?
  var randomizeStartPosition: Bool?
  var loopSound: Bool?  // nil = default (true), false = play once and deselect
  var fadeSound: Bool?  // nil = default (true), false = hard cut on play/pause
  var isPresetUseOnly: Bool?  // nil = default (false), true = hidden outside presets
  var isMusic: Bool?  // nil = default (sound's JSON value), overrides the music tag

  // Audio normalization settings
  var normalizeAudio: Bool?
  var volumeAdjustment: Float?  // 0.5 = -50%, 1.0 = normal, 1.5 = +50%

  init(
    fileName: String, customTitle: String? = nil, customIconName: String? = nil,
    randomizeStartPosition: Bool? = nil,
    normalizeAudio: Bool? = nil, volumeAdjustment: Float? = nil, loopSound: Bool? = nil,
    fadeSound: Bool? = nil, isPresetUseOnly: Bool? = nil, isMusic: Bool? = nil
  ) {
    self.id = UUID()
    self.fileName = fileName
    self.customTitle = customTitle
    self.customIconName = customIconName
    self.randomizeStartPosition = randomizeStartPosition
    self.normalizeAudio = normalizeAudio
    self.volumeAdjustment = volumeAdjustment
    self.loopSound = loopSound
    self.fadeSound = fadeSound
    self.isPresetUseOnly = isPresetUseOnly
    self.isMusic = isMusic
  }

  /// Returns the effective title (custom or original)
  func effectiveTitle(originalTitle: String) -> String {
    return customTitle ?? originalTitle
  }

  /// Returns the effective icon name (custom or original)
  func effectiveIconName(originalIconName: String) -> String {
    return customIconName ?? originalIconName
  }

  /// Whether this customization has any custom values
  var hasCustomizations: Bool {
    return customTitle != nil || customIconName != nil
      || randomizeStartPosition != nil || normalizeAudio != nil || volumeAdjustment != nil
      || loopSound != nil || fadeSound != nil || isPresetUseOnly != nil || isMusic != nil
  }
}

/// Manager for built-in sound customizations
@Observable
class SoundCustomizationManager {
  static let shared = SoundCustomizationManager()

  private var customizations: [String: SoundCustomization] = [:]

  private let userDefaultsKey = "soundCustomizations"

  private init() {
    loadCustomizations()
  }

  /// Get customization for a specific sound file name
  func getCustomization(for fileName: String) -> SoundCustomization? {
    return customizations[fileName]
  }

  /// Get-or-create the customization, apply one field, prune it if empty, then save.
  /// Single owner of the mutation/prune/save policy shared by every setter below.
  private func mutate(for fileName: String, _ body: (inout SoundCustomization) -> Void) {
    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    body(&customization)

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set custom title for a sound
  func setCustomTitle(_ title: String?, for fileName: String) {
    if title?.isEmpty == true {
      setCustomTitle(nil, for: fileName)
      return
    }

    mutate(for: fileName) { $0.customTitle = title }
  }

  /// Set custom icon for a sound
  func setCustomIcon(_ iconName: String?, for fileName: String) {
    if iconName?.isEmpty == true {
      setCustomIcon(nil, for: fileName)
      return
    }

    mutate(for: fileName) { $0.customIconName = iconName }
  }

  /// Set randomize start position for a sound
  func setRandomizeStartPosition(_ randomize: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.randomizeStartPosition = randomize }
  }

  /// Set normalize audio for a sound
  func setNormalizeAudio(_ normalize: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.normalizeAudio = normalize }
  }

  /// Set volume adjustment for a sound
  func setVolumeAdjustment(_ adjustment: Float?, for fileName: String) {
    mutate(for: fileName) { $0.volumeAdjustment = adjustment }
  }

  /// Set loop sound for a sound
  func setLoopSound(_ loop: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.loopSound = loop }
  }

  /// Set fade in/out for a sound
  func setFadeSound(_ fade: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.fadeSound = fade }
  }

  /// Set preset-use-only for a sound
  func setPresetUseOnly(_ presetOnly: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.isPresetUseOnly = presetOnly }
  }

  /// Set music tag for a sound
  func setMusic(_ music: Bool?, for fileName: String) {
    mutate(for: fileName) { $0.isMusic = music }
  }

  /// Reset all customizations for a specific sound
  func resetCustomizations(for fileName: String) {
    customizations.removeValue(forKey: fileName)
    saveCustomizationsInternal()
  }

  /// Reset all customizations for all sounds
  func resetAllCustomizations() {
    customizations.removeAll()
    saveCustomizationsInternal()
  }

  /// Get or create customization for a specific sound file name
  func getOrCreateCustomization(for fileName: String) -> SoundCustomization {
    if let existing = customizations[fileName] {
      return existing
    } else {
      let new = SoundCustomization(fileName: fileName)
      customizations[fileName] = new
      return new
    }
  }

  /// Remove customization for a specific sound
  func removeCustomization(for fileName: String) {
    customizations.removeValue(forKey: fileName)
    saveCustomizationsInternal()
  }

  /// Save customizations manually (public version)
  func saveCustomizations() {
    saveCustomizationsInternal()
  }

  /// Get all customized sound file names
  var customizedSounds: [String] {
    return Array(customizations.keys)
  }

  /// Whether any sounds have customizations
  var hasAnyCustomizations: Bool {
    return !customizations.isEmpty
  }

  /// Get all customizations
  func getAllCustomizations() -> [SoundCustomization] {
    return Array(customizations.values)
  }

  // MARK: - Persistence

  @ObservationIgnored private var saveTimer: Timer?

  private func saveCustomizationsInternal() {
    // Debounce saves to avoid excessive UserDefaults writes during initialization
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.performSave() }
    }
  }

  private func performSave() {
    do {
      let data = try JSONEncoder().encode(Array(customizations.values))
      UserDefaults.shared.set(data, forKey: userDefaultsKey)
      Logger.sounds.debug(
        "SoundCustomizationManager: Saved \(self.customizations.count) customizations")
    } catch {
      Logger.sounds.error(
        "SoundCustomizationManager: Failed to save customizations: \(error, privacy: .public)")
    }
  }

  private func loadCustomizations() {

    guard let data = UserDefaults.shared.data(forKey: userDefaultsKey) else {
      Logger.sounds.debug("SoundCustomizationManager: No saved customizations found")
      return
    }

    do {
      let customizationArray = try JSONDecoder().decode([SoundCustomization].self, from: data)
      // uniquingKeysWith (not uniqueKeysWithValues) so a duplicate fileName in
      // the persisted array can't trap at launch - last entry wins.
      customizations = Dictionary(
        customizationArray.map { ($0.fileName, $0) }, uniquingKeysWith: { $1 })
      Logger.sounds.debug(
        "SoundCustomizationManager: Loaded \(self.customizations.count) customizations")
    } catch {
      Logger.sounds.error(
        "SoundCustomizationManager: Failed to load customizations: \(error, privacy: .public)")
      customizations = [:]
    }
  }
}
