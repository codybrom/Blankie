//
//  CarPlayNowPlayingExtensions.swift
//  Blankie
//
//  Created by Cody Bromley on 9/20/25.
//

// `canImport(CarPlay)` keeps this out of the macOS build: CarPlay ships only on
// iOS, so even when CARPLAY_ENABLED is defined the `import CarPlay` must not be
// parsed where the framework doesn't exist.
#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import MediaPlayer
  import SwiftUI

  extension CarPlayInterfaceController {
    /// Setup the Now Playing template with edit functionality (only when not in solo mode)
    @MainActor
    func setupNowPlayingTemplate() {
      let nowPlayingTemplate = CPNowPlayingTemplate.shared

      // Buttons show only when a preset is playing. This already excludes Quick
      // Mix — entering it clears `currentPreset` — and solo mode. Quick Mix has
      // its own CarPlay tab and isn't favoritable.
      if AudioManager.shared.soloModeSound == nil, let preset = PresetManager.shared.currentPreset {
        let favoriteToken =
          preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
        let isFavorite = GlobalSettings.shared.isStarred(favoriteToken)
        let favoriteButton = CPNowPlayingImageButton(
          image: UIImage(systemName: isFavorite ? "star.fill" : "star")!
        ) { [weak self] _ in
          Task { @MainActor in
            GlobalSettings.shared.toggleStarred(favoriteToken)
            self?.updateNowPlayingButtons()
          }
        }

        let editButton = CPNowPlayingImageButton(image: UIImage(systemName: "slider.horizontal.3")!)
        { [weak self] _ in
          Task { @MainActor in
            self?.showEditSoundsInterface()
          }
        }

        nowPlayingTemplate.updateNowPlayingButtons([favoriteButton, editButton])
        debugLog("✅ CarPlay: Now Playing configured with favorite + edit buttons (preset mode)")
      } else {
        // Solo mode or Quick Mix: no preset-specific buttons.
        nowPlayingTemplate.updateNowPlayingButtons([])
        debugLog("✅ CarPlay: Now Playing configured with no custom buttons (solo / Quick Mix)")
      }
    }

    /// Update Now Playing buttons based on current playback state
    @MainActor
    func updateNowPlayingButtons() {
      setupNowPlayingTemplate()
    }

    /// Alternative approach: Add edit button to a custom information template
    @MainActor
    func showNowPlayingWithEdit() {
      guard let interfaceController = currentInterfaceController else { return }

      // Create an information template that shows current playing info with edit option
      let infoTemplate = createNowPlayingInfoTemplate()

      interfaceController.pushTemplate(infoTemplate, animated: true, completion: nil)
    }

    /// Creates an information template showing current playing state with edit access
    @MainActor
    private func createNowPlayingInfoTemplate() -> CPInformationTemplate {
      // Get current preset info
      let currentPreset = PresetManager.shared.currentPreset
      let playingSounds = AudioManager.shared.sounds.filter { $0.isSelected }

      let title = currentPreset?.name ?? "Custom Mix"
      let detail =
        playingSounds.isEmpty ? "No sounds selected" : "\(playingSounds.count) sounds playing"

      // Create information items
      var items: [CPInformationItem] = []

      // Add current preset info
      let presetItem = CPInformationItem(title: "Current Preset", detail: title)
      items.append(presetItem)

      // Add sound count info
      let soundsItem = CPInformationItem(title: "Active Sounds", detail: detail)
      items.append(soundsItem)

      // Add playing sounds list
      if !playingSounds.isEmpty {
        for sound in playingSounds.prefix(5) {  // Limit to first 5 for display
          let volumeText = "\(Int(sound.volume * 100))%"
          let soundItem = CPInformationItem(title: sound.title, detail: "Volume: \(volumeText)")
          items.append(soundItem)
        }

        if playingSounds.count > 5 {
          let moreItem = CPInformationItem(
            title: "...", detail: "and \(playingSounds.count - 5) more")
          items.append(moreItem)
        }
      }

      let template = CPInformationTemplate(
        title: "Now Playing", layout: .leading, items: items, actions: [])

      // Add edit button
      let editButton = CPBarButton(title: "Edit") { [weak self] _ in
        Task { @MainActor in
          self?.showEditSoundsInterface()
        }
      }

      template.trailingNavigationBarButtons = [editButton]

      return template
    }

    /// Update the Now Playing template when needed
    @MainActor
    func updateNowPlayingTemplate() {
      // Re-setup the Now Playing buttons if needed
      setupNowPlayingTemplate()
    }
  }

#endif
