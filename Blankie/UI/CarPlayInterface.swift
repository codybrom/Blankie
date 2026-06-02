// CarPlayInterface.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import Combine
  import SwiftUI

  class CarPlayInterface: ObservableObject {
    static let shared = CarPlayInterface()

    @Published private(set) var isConnected = false
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    private init() {
      // Set up observers for audio manager and preset manager changes
      observeAudioManagerChanges()
      observePresetManagerChanges()
    }

    func setInterfaceController(_ controller: CPInterfaceController) {
      interfaceController = controller
      isConnected = true
      updateInterface()

      // Post notification about CarPlay connection
      NotificationCenter.default.post(
        name: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        userInfo: ["isConnected": true]
      )
    }

    @MainActor
    func disconnect() {
      interfaceController = nil
      isConnected = false

      // Exit solo mode if active
      if AudioManager.shared.soloModeSound != nil {
        AudioManager.shared.exitSoloMode()
      }

      // Post notification about CarPlay disconnection
      NotificationCenter.default.post(
        name: NSNotification.Name("CarPlayConnectionChanged"),
        object: nil,
        userInfo: ["isConnected": false]
      )
    }

    // MARK: - Interface Management

    func updateInterface() {
      guard isConnected, let interfaceController = interfaceController else { return }

      debugLog("🚗 CarPlay: Updating interface at \(Date())")

      // Just show the preset list
      let presetsTemplate = createPresetsTemplate()

      // Force update by setting root template
      interfaceController.setRootTemplate(presetsTemplate, animated: false, completion: nil)
    }

    // MARK: - Template Creation

    private func createPresetsTemplate() -> CPTemplate {
      var sections: [CPListSection] = []

      // Get custom presets (non-default)
      let customPresets = PresetManager.shared.presets.filter { !$0.isDefault }
      let defaultPreset = PresetManager.shared.presets.first { $0.isDefault }

      if customPresets.isEmpty && defaultPreset != nil {
        // No custom presets - show default as "Current Soundscape"
        if let defaultPreset = defaultPreset {
          let currentSoundscapeItem = createCurrentSoundscapeItem(defaultPreset)
          sections.append(
            CPListSection(
              items: [currentSoundscapeItem], header: String(localized: "Presets"),
              sectionIndexTitle: "P")
          )
        }
      } else if !customPresets.isEmpty {
        // Has custom presets - only show custom presets, not default
        let presetItems = customPresets.map { createPresetListItem($0) }
        sections.append(
          CPListSection(
            items: presetItems, header: String(localized: "Presets"), sectionIndexTitle: "P"))
      }

      // Individual sounds section
      let allSounds = AudioManager.shared.sounds
      let soundItems = allSounds.map { createSoundListItem($0) }
      if !soundItems.isEmpty {
        sections.append(
          CPListSection(
            items: soundItems, header: String(localized: "Sounds"),
            sectionIndexTitle: "S"))
      }

      return CPListTemplate(title: "Blankie", sections: sections)
    }

    private func createCurrentSoundscapeItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId
      let activeIndicator = isActive ? " ✓" : ""

      let item = CPListItem(
        text: "\(String(localized: "Current Soundscape"))\(activeIndicator)",
        detailText: getPresetDetailText(preset))

      // Use a weak capture to avoid the 'self' in concurrently-executing code error
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          self?.applyPresetAndStartPlayback(preset)
          completion()
        }
      }

      return item
    }

    private func createPresetListItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId
      let activeIndicator = isActive ? " ✓" : ""

      debugLog(
        "🚗 CarPlay: Creating preset item '\(preset.name)' - isActive: \(isActive), currentPresetId: \(currentPresetId?.uuidString ?? "nil")"
      )

      let item = CPListItem(
        text: "\(preset.name)\(activeIndicator)", detailText: getPresetDetailText(preset))

      // Use a weak capture to avoid the 'self' in concurrently-executing code error
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          self?.applyPresetAndStartPlayback(preset)
          completion()
        }
      }

      return item
    }

    private func getPresetDetailText(_ preset: Preset) -> String {
      let activeSounds = preset.soundStates.filter { $0.isSelected }
      if activeSounds.isEmpty {
        return String(localized: "No active sounds")
      } else {
        // List the first few sound names
        let soundNames = activeSounds.prefix(3).map { soundState in
          AudioManager.shared.sounds.first { $0.fileName == soundState.fileName }?.title
            ?? soundState.fileName
        }
        let joined = soundNames.joined(separator: ", ")
        if activeSounds.count > 3 {
          let remaining = activeSounds.count - 3
          return String(localized: "\(joined) and \(remaining) more")
        } else {
          return joined
        }
      }
    }

    private func createSoundListItem(_ sound: Sound) -> CPListItem {
      let isInSoloMode = AudioManager.shared.soloModeSound?.id == sound.id
      let activeIndicator = isInSoloMode ? " ✓" : ""

      // Always show the sound's real name in the car. "Show Sound Names" is a
      // phone-screen preference; surfacing the raw SF Symbol identifier (e.g.
      // "cloud.rain") to a driver is neither useful nor HIG-compliant.
      let item = CPListItem(
        text: "\(sound.title)\(activeIndicator)",
        detailText: sound.isCustom ? String(localized: "Custom sound") : nil
      )

      // Use a weak capture to avoid the 'self' in concurrently-executing code error
      item.handler = {
        [weak self] (_: any CPSelectableListItem, completion: @escaping () -> Void) in
        Task { @MainActor in
          await self?.playIndividualSound(sound)
          completion()
        }
      }

      return item
    }

    /// Apply a preset, start playback, then surface the Now Playing screen —
    /// mirrors the individual-sound path so CarPlay shows Now Playing once audio
    /// is ready. Kept on the main actor so `self` access is concurrency-safe
    /// under the Swift 6 language mode.
    @MainActor
    private func applyPresetAndStartPlayback(_ preset: Preset) {
      do {
        try PresetManager.shared.applyPreset(preset)
        // Always ensure playback starts when selecting a preset in CarPlay.
        AudioManager.shared.setGlobalPlaybackState(true)
        interfaceController?.pushTemplate(
          CPNowPlayingTemplate.shared, animated: true, completion: nil)
      } catch {
        debugLog("🚗 CarPlay: Error applying preset: \(error)")
      }
    }

    @MainActor
    private func playIndividualSound(_ sound: Sound) async {
      debugLog("🚗 CarPlay: Playing individual sound '\(sound.title)'")

      // Toggle solo mode for this sound
      AudioManager.shared.toggleSoloMode(for: sound)

      // Show Now Playing screen
      if let interfaceController = interfaceController {
        interfaceController.pushTemplate(
          CPNowPlayingTemplate.shared, animated: true, completion: nil)
      }

    }

    // MARK: - Observers

    private func observeAudioManagerChanges() {
      // Observe global playback state
      AudioManager.shared.$isGloballyPlaying
        .sink { [weak self] isPlaying in
          debugLog("🚗 CarPlay: Playback state changed to: \(isPlaying)")
          // Only update if we're showing the root template (not Now Playing)
          if let interfaceController = self?.interfaceController,
            interfaceController.topTemplate === interfaceController.rootTemplate
          {
            debugLog("🚗 CarPlay: Updating interface for playback state change")
            self?.updateInterface()
          }
        }
        .store(in: &cancellables)
    }

    private func observePresetManagerChanges() {
      // Observe current preset with debouncing
      PresetManager.shared.$currentPreset
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] preset in
          debugLog("🚗 CarPlay: Current preset changed to: \(preset?.name ?? "nil")")
          self?.updateInterface()
        }
        .store(in: &cancellables)

      // Also observe presets array changes with debouncing
      PresetManager.shared.$presets
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          debugLog("🚗 CarPlay: Presets array changed")
          self?.updateInterface()
        }
        .store(in: &cancellables)
    }
  }

#endif
