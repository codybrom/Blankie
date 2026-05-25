// CarPlayInterface.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//

#if CARPLAY_ENABLED

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
            CPListSection(items: [currentSoundscapeItem], header: "Presets", sectionIndexTitle: "P")
          )
        }
      } else if !customPresets.isEmpty {
        // Has custom presets - only show custom presets, not default
        let presetItems = customPresets.map { createPresetListItem($0) }
        sections.append(
          CPListSection(items: presetItems, header: "Presets", sectionIndexTitle: "P"))
      }

      // Individual sounds section
      let allSounds = AudioManager.shared.sounds
      let soundItems = allSounds.map { createSoundListItem($0) }
      if !soundItems.isEmpty {
        sections.append(
          CPListSection(items: soundItems, header: "Individual Sounds", sectionIndexTitle: "S"))
      }

      return CPListTemplate(title: "Blankie", sections: sections)
    }

    private func createCurrentSoundscapeItem(_ preset: Preset) -> CPListItem {
      let currentPresetId = PresetManager.shared.currentPreset?.id
      let isActive = preset.id == currentPresetId
      let activeIndicator = isActive ? " ✓" : ""

      let item = CPListItem(
        text: "Current Soundscape\(activeIndicator)", detailText: getPresetDetailText(preset))

      // Use a weak capture to avoid the 'self' in concurrently-executing code error
      item.handler = { _, completion in
        Task {
          do {
            try await PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Always ensure playback starts when selecting a preset in CarPlay
              AudioManager.shared.setGlobalPlaybackState(true)
            }
          } catch {
            debugLog("🚗 CarPlay: Error applying preset: \(error)")
          }
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
      item.handler = { _, completion in
        Task {
          do {
            try await PresetManager.shared.applyPreset(preset)
            await MainActor.run {
              // Always ensure playback starts when selecting a preset in CarPlay
              AudioManager.shared.setGlobalPlaybackState(true)
            }
          } catch {
            debugLog("🚗 CarPlay: Error applying preset: \(error)")
          }
          completion()
        }
      }

      return item
    }

    private func getPresetDetailText(_ preset: Preset) -> String {
      let activeSounds = preset.soundStates.filter { $0.isSelected }
      if activeSounds.isEmpty {
        return "No active sounds"
      } else {
        // List the first few sound names
        let soundNames = activeSounds.prefix(3).map { soundState in
          AudioManager.shared.sounds.first { $0.fileName == soundState.fileName }?.title
            ?? soundState.fileName
        }
        if activeSounds.count > 3 {
          return "\(soundNames.joined(separator: ", ")) and \(activeSounds.count - 3) more"
        } else {
          return soundNames.joined(separator: ", ")
        }
      }
    }

    private func createSoundListItem(_ sound: Sound) -> CPListItem {
      let isInSoloMode = AudioManager.shared.soloModeSound?.id == sound.id
      let activeIndicator = isInSoloMode ? " ✓" : ""

      // Use icon name if sound names are hidden
      let displayText = GlobalSettings.shared.showSoundNames ? sound.title : sound.systemIconName

      let item = CPListItem(
        text: "\(displayText)\(activeIndicator)",
        detailText: sound.isCustom ? "Custom sound" : nil
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
