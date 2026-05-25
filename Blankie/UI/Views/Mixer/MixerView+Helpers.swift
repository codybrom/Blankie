//
//  MixerView+Helpers.swift
//  Blankie
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension MixerView {
    // Calculate filtered sounds based on current preset and hideInactiveSounds preference
    var filteredSounds: [Sound] {
      return filterSounds()
    }

    private func filterSounds() -> [Sound] {
      let visibleSounds = audioManager.getVisibleSounds()

      let filteredSounds = visibleSounds.filter { sound in
        guard let currentPreset = presetManager.currentPreset else {
          // No current preset — show everything.
          return true
        }
        // Default preset shows all sounds; a custom preset shows only the
        // sounds that belong to it.
        if currentPreset.isDefault {
          return true
        }
        return currentPreset.soundStates.contains { $0.fileName == sound.fileName }
      }

      // Sort filtered sounds according to preset order or default sound order
      if let currentPreset = presetManager.currentPreset,
        !currentPreset.isDefault,
        let soundOrder = currentPreset.soundOrder
      {
        // Use preset's sound order for custom presets
        debugLog("🔍 FilteredSounds: Using preset order: \(soundOrder)")
        let orderDict = Dictionary(uniqueKeysWithValues: soundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      } else {
        // Use default sound order for default preset or no preset
        debugLog("🔍 FilteredSounds: Using default order: \(audioManager.defaultSoundOrder)")
        let orderDict = Dictionary(
          uniqueKeysWithValues: audioManager.defaultSoundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      }
    }

    // Determine if we're on iPad or Mac
    var isLargeDevice: Bool {
      horizontalSizeClass == .regular
    }

    // MARK: - Helper Properties

    var hasSelectedSounds: Bool {
      audioManager.hasSelectedSounds
    }

    // MARK: - Preset Background

    @ViewBuilder
    var presetBackgroundView: some View {
      let preset = presetManager.currentPreset

      GeometryReader { geometry in
        ZStack {
          // Layer 1: Animated artwork preview image (blurred) — only when
          // a custom artwork exists. Presets without artwork fall through
          // to the shared accent gradient (same look as Quick Mix).
          if preset != nil,
            let artworkImage = backgroundImage
          {
            Image(uiImage: artworkImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .blur(radius: 20)
              .opacity(0.6)
              .clipped()
              .overlay(
                Color.black.opacity(0.15)
              )
          }
          // Layer 2: Shared accent gradient — matches Quick Mix so the
          // default preset, custom accent presets, and Quick Mix all read
          // as variants of the same surface.
          else {
            SoundSurfaceBackground(
              accent: preset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
            )
          }
        }
      }
      .ignoresSafeArea()
      .task(
        id:
          "\(preset?.id.uuidString ?? "")-\(preset?.artworkId?.uuidString ?? "")-\(preset?.animatedArtwork?.previewPath ?? "")"
      ) {
        guard let preset = preset else {
          backgroundImage = nil
          return
        }
        backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
      }
    }
  }

  /// Shared background used by both the main tile grid (non-artwork presets)
  /// and Quick Mix so the two modes read as one visual system.
  struct SoundSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    var body: some View {
      // The base (bottom) stop must adapt: a hardcoded near-black makes the
      // grid/Quick Mix render black-on-black under the Light appearance (tile
      // text is `.primary`). Dark keeps the deep look; Light falls back to the
      // system background, matching the pre-unification main-grid surface.
      let base =
        colorScheme == .dark
        ? Color.black.opacity(0.9)
        : Color(.systemBackground).opacity(0.5)

      LinearGradient(
        colors: [
          accent.opacity(0.25),
          accent.opacity(0.1),
          base,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
    }
  }
#endif
