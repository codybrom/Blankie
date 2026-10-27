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
        return preset.displayName
      }

      return "Blankie"
    }

    // MARK: - Preset Page Header (regular width)

    /// The regular layout names the preset above its sounds; Solo and Quick
    /// Mix have their own surfaces.
    /// Skipped when height is compact (a large iPhone in landscape), where the
    /// tiles need the room and the nav title names the preset instead.
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

    /// The Edit affordance for whatever is on screen — the Quick Mix editor, the
    /// current preset, or the solo sound's editor — plus Spatial Mix when it's
    /// on. A real item group (titled labels, no custom view) so iPhone Duo can
    /// move it into the side bar; Edit is the last to overflow.
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
        // Toolbar buttons draw their symbol from the tint, so the accent has to
        // be overridden here rather than via foregroundStyle on the label.
        .tint(.primary)
        .disabled(target == nil)
        // An empty preset can only get sounds from its editor.
        .badge(
          presetManager.currentPresetHasNoSounds && !presetManager.isLoading
            ? Text(verbatim: "!") : nil)
      }
    }

    /// What the Edit button targets: the solo sound's editor, the Quick Mix
    /// editor, or the current preset. The default preset has no editor —
    /// there, the slot becomes a New Preset affordance (confirm, then the
    /// creator seeded with the playing sounds). `nil` when there's nothing to
    /// edit (the button renders disabled rather than vanishing, so the slot
    /// never collapses).
    var editTarget: (icon: String, label: String, action: () -> Void)? {
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
