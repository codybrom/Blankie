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
      // Solo's inline player already shows the sound name under the artwork.
      if audioManager.soloModeSound != nil {
        return ""
      }

      if audioManager.isQuickMix {
        return String(localized: "Quick Mix")
      }

      if let preset = presetManager.currentPreset {
        return preset.displayName
      }

      return "Blankie"
    }

    // MARK: - Preset Page Header (regular width)

    /// Preset name above the sounds in the regular layout. Skipped in compact
    /// height (large iPhone in landscape), where the nav title names the preset.
    var showsPresetPageHeader: Bool {
      verticalSizeClass != .compact
        && !presetManager.isLoading && audioManager.soloModeSound == nil
        && !audioManager.isQuickMix && presetManager.currentPreset != nil
    }

    @ViewBuilder
    var presetPageHeader: some View {
      if let preset = presetManager.currentPreset {
        HStack(spacing: 18) {
          Group {
            if let image = backgroundImage {
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
              FallbackArtwork(
                glyph: .playback(
                  isQuickMix: false, isDefaultPreset: preset.isDefault,
                  icons: audioManager.playingSoundIcons()),
                accent: preset.accentColor ?? globalSettings.customAccentColor ?? .accentColor,
                size: 96,
                glyphFraction: 0.5
              )
            }
          }
          .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 2) {
            Text(preset.activeTitle)
              .font(.title2.bold())
              .lineLimit(2)
            if let creator = preset.creatorName, !creator.isEmpty {
              Text(creator)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)

          Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
      }
    }

    // MARK: - Top Bar Trailing Items

    /// Edit (plus Spatial Mix when enabled). A plain item group with titled
    /// labels so iPhone Duo can move it into the side bar; Edit overflows last.
    @ToolbarContentBuilder
    var editToolbarItems: some ToolbarContent {
      #if os(iOS)
        if #available(iOS 27, *) {
          editToolbarGroup.visibilityPriority(.high)
        } else {
          editToolbarGroup
        }
      #else
        editToolbarGroup
      #endif
    }

    @ToolbarContentBuilder
    private var editToolbarGroup: some ToolbarContent {
      let target = editTarget
      ToolbarItemGroup(placement: .topBarTrailing) {
        if globalSettings.enableSpatialAudio,
          audioManager.soloModeSound == nil, !audioManager.isQuickMix,
          presetManager.currentPreset != nil
        {
          Button {
            showingSpatialMixer = true
          } label: {
            // person.spatialaudio.* symbols are restricted to Apple's Spatial Audio feature.
            Label("Spatial Mix", systemImage: "speaker.wave.1.arrowtriangles.up.right.down.left")
          }
          .tint(.primary)
        }

        Button {
          target?.action()
        } label: {
          Label(
            LocalizedStringKey(target?.label ?? "Edit Preset"),
            systemImage: target?.icon ?? "slider.vertical.3")
        }
        // Toolbar buttons draw their symbol from the tint.
        .tint(.primary)
        .disabled(target == nil)
        // An empty preset can only get sounds from its editor.
        .badge(
          presetManager.currentPresetHasNoSounds && !presetManager.isLoading
            ? Text(verbatim: "!") : nil)
      }
    }

    /// The default preset has no editor, so its slot becomes New Preset (seeded
    /// with the playing sounds). `nil` renders the button disabled.
    var editTarget: (icon: String, label: String, action: () -> Void)? {
      if let soloSound = audioManager.soloModeSound {
        return ("slider.vertical.3", "Edit Sound", { soundToEdit = soloSound })
      } else if audioManager.isQuickMix {
        return ("slider.vertical.3", "Edit Quick Mix", { showingQuickMixEditor = true })
      } else if let currentPreset = presetManager.currentPreset {
        if currentPreset.isDefault {
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
