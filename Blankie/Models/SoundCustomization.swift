//
//  SoundCustomization.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import Foundation
import SwiftUI

/// Represents customizations applied to built-in sounds
struct SoundCustomization: Codable, Identifiable {
  let id: UUID
  let fileName: String
  var customTitle: String?
  var customIconName: String?
  var customColorName: String?
  var randomizeStartPosition: Bool?
  var loopSound: Bool?  // nil = default (true), false = play once and deselect

  // Audio normalization settings
  var normalizeAudio: Bool?
  var volumeAdjustment: Float?  // 0.5 = -50%, 1.0 = normal, 1.5 = +50%

  init(
    fileName: String, customTitle: String? = nil, customIconName: String? = nil,
    customColorName: String? = nil, randomizeStartPosition: Bool? = nil,
    normalizeAudio: Bool? = nil, volumeAdjustment: Float? = nil, loopSound: Bool? = nil
  ) {
    self.id = UUID()
    self.fileName = fileName
    self.customTitle = customTitle
    self.customIconName = customIconName
    self.customColorName = customColorName
    self.randomizeStartPosition = randomizeStartPosition
    self.normalizeAudio = normalizeAudio
    self.volumeAdjustment = volumeAdjustment
    self.loopSound = loopSound
  }

  /// Returns the effective title (custom or original)
  func effectiveTitle(originalTitle: String) -> String {
    return customTitle ?? originalTitle
  }

  /// Returns the effective icon name (custom or original)
  func effectiveIconName(originalIconName: String) -> String {
    return customIconName ?? originalIconName
  }

  /// Returns the effective color (custom or nil for default)
  var effectiveColor: Color? {
    guard let colorName = customColorName else { return nil }
    return Color(fromString: colorName)
  }

  /// Whether this customization has any custom values
  var hasCustomizations: Bool {
    return customTitle != nil || customIconName != nil || customColorName != nil
      || randomizeStartPosition != nil || normalizeAudio != nil || volumeAdjustment != nil
      || loopSound != nil
  }
}

/// Manager for built-in sound customizations
class SoundCustomizationManager: ObservableObject {
  static let shared = SoundCustomizationManager()

  @Published private var customizations: [String: SoundCustomization] = [:]

  private let userDefaultsKey = "soundCustomizations"

  private init() {
    loadCustomizations()
  }

  /// Get customization for a specific sound file name
  func getCustomization(for fileName: String) -> SoundCustomization? {
    return customizations[fileName]
  }

  /// Set custom title for a sound
  func setCustomTitle(_ title: String?, for fileName: String) {
    if title?.isEmpty == true {
      setCustomTitle(nil, for: fileName)
      return
    }

    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.customTitle = title

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set custom icon for a sound
  func setCustomIcon(_ iconName: String?, for fileName: String) {
    if iconName?.isEmpty == true {
      setCustomIcon(nil, for: fileName)
      return
    }

    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.customIconName = iconName

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set custom color for a sound
  func setCustomColor(_ colorName: String?, for fileName: String) {
    if colorName?.isEmpty == true {
      setCustomColor(nil, for: fileName)
      return
    }

    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.customColorName = colorName

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set randomize start position for a sound
  func setRandomizeStartPosition(_ randomize: Bool?, for fileName: String) {
    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.randomizeStartPosition = randomize

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set normalize audio for a sound
  func setNormalizeAudio(_ normalize: Bool?, for fileName: String) {
    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.normalizeAudio = normalize

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set volume adjustment for a sound
  func setVolumeAdjustment(_ adjustment: Float?, for fileName: String) {
    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.volumeAdjustment = adjustment

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
  }

  /// Set loop sound for a sound
  func setLoopSound(_ loop: Bool?, for fileName: String) {
    var customization = customizations[fileName] ?? SoundCustomization(fileName: fileName)
    customization.loopSound = loop

    if customization.hasCustomizations {
      customizations[fileName] = customization
    } else {
      customizations.removeValue(forKey: fileName)
    }

    saveCustomizationsInternal()
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

  private func saveCustomizationsInternal() {
    do {
      let data = try JSONEncoder().encode(Array(customizations.values))
      UserDefaults.standard.set(data, forKey: userDefaultsKey)
      print("✅ SoundCustomizationManager: Saved \(customizations.count) customizations")
    } catch {
      print("❌ SoundCustomizationManager: Failed to save customizations: \(error)")
    }
  }

  private func loadCustomizations() {
    guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
      print("📦 SoundCustomizationManager: No saved customizations found")
      return
    }

    do {
      let customizationArray = try JSONDecoder().decode([SoundCustomization].self, from: data)
      customizations = Dictionary(
        uniqueKeysWithValues: customizationArray.map { ($0.fileName, $0) })
      print("✅ SoundCustomizationManager: Loaded \(customizations.count) customizations")
    } catch {
      print("❌ SoundCustomizationManager: Failed to load customizations: \(error)")
      customizations = [:]
    }
  }
}
