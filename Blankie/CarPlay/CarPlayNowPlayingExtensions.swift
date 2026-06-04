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
        debugLog("CarPlay: Now Playing configured with favorite + edit buttons (preset mode)", .carPlay)
      } else {
        // Solo mode or Quick Mix: no preset-specific buttons.
        nowPlayingTemplate.updateNowPlayingButtons([])
        debugLog("CarPlay: Now Playing configured with no custom buttons (solo / Quick Mix)", .carPlay)
      }
    }

    /// Update Now Playing buttons based on current playback state
    @MainActor
    func updateNowPlayingButtons() {
      setupNowPlayingTemplate()
    }
  }

#endif
