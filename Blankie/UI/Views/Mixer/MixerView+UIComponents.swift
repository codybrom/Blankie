//
//  MixerView+UIComponents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)

  // MARK: - UI Components Extension

  extension MixerView {
    // MARK: - Navigation Elements

    var navigationTitle: String {
      // Solo renders the full inline now-playing player, which shows the sound
      // name under the artwork — leave the nav heading empty so it isn't shown
      // twice.
      if audioManager.soloModeSound != nil {
        return ""
      }

      if audioManager.isQuickMix {
        return String(localized: "Quick Mix")
      }

      if let preset = presetManager.currentPreset {
        return preset.isDefault ? "Blankie" : preset.name
      }

      return "Blankie"
    }

    // MARK: - Top Bar Trailing Button

    /// Top-trailing nav bar slot, identical on iPhone and iPad: the Edit
    /// affordance for whatever is on screen — the Quick Mix editor, the current
    /// preset, or the solo sound's editor. The nav bar supplies the Liquid
    /// Glass treatment.
    var topTrailingToolbarButton: some View {
      let target = editTarget
      return HStack(spacing: 2) {
        // Spatial mixer entry — preset mode only, and only when the user has
        // opted into the experimental feature in Settings
        if globalSettings.enableSpatialAudio,
          audioManager.soloModeSound == nil, !audioManager.isQuickMix,
          presetManager.currentPreset != nil
        {
          Button {
            showingSpatialMixer = true
          } label: {
            // Not person.spatialaudio.*: those are restricted to referring to
            // Apple's Spatial Audio feature, and our spatial mix is an in-app
            // binaural render, not the system feature.
            Image(systemName: "speaker.wave.1.arrowtriangles.up.right.down.left")
          }
          .tint(.primary)
          .accessibilityLabel(Text("Spatial Mix"))
        }

        Button {
          target?.action()
        } label: {
          Image(systemName: target?.icon ?? "slider.vertical.3")
        }
        // Toolbar buttons draw their symbol from the tint, so the accent has to
        // be overridden here rather than via foregroundStyle on the label.
        .tint(.primary)
        .accessibilityLabel(target?.label ?? "Edit Preset")
        .disabled(target == nil)
      }
    }

    /// What the Edit button targets: the solo sound's editor, the Quick Mix
    /// editor, or the current preset. The default preset has no editor —
    /// there, the slot becomes a New Preset affordance (confirm, then the
    /// creator seeded with the playing sounds). `nil` when there's nothing to
    /// edit (the button renders disabled rather than vanishing, so the slot
    /// never collapses).
    private var editTarget: (icon: String, label: String, action: () -> Void)? {
      if let soloSound = audioManager.soloModeSound {
        return ("slider.vertical.3", "Edit Sound", { soundToEdit = soloSound })
      } else if audioManager.isQuickMix {
        return ("slider.vertical.3", "Edit Quick Mix", { showingQuickMixEditor = true })
      } else if let currentPreset = presetManager.currentPreset {
        if currentPreset.isDefault {
          // Nothing playing means nothing to seed the new preset with.
          guard audioManager.hasSelectedSounds else { return nil }
          return (
            "rectangle.stack.badge.plus", "New Preset", { showingNewPresetConfirmation = true }
          )
        }
        return ("slider.vertical.3", "Edit Preset", { presetToEdit = currentPreset })
      } else {
        return nil
      }
    }
  }

#endif
