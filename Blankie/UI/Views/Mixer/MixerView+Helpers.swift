//
//  MixerView+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 2/22/26.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension MixerView {
    // Filtered + ordered sounds for the current preset (shared with macOS).
    var filteredSounds: [Sound] {
      audioManager.orderedVisibleSounds(for: presetManager.currentPreset)
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
      // Solo is its own thing — it shouldn't inherit the last preset's artwork.
      // It uses the shared accent gradient (app accent), like Quick Mix.
      let isSolo = audioManager.soloModeSound != nil

      GeometryReader { geometry in
        ZStack {
          // Layer 1: Animated artwork preview image (blurred) — only when
          // a custom artwork exists (and not in solo mode). Presets without
          // artwork fall through to the shared accent gradient.
          if !isSolo, preset != nil,
            let artworkImage = backgroundImage
          {
            Image(uiImage: artworkImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              // Per-preset override wins; otherwise fall back to the app-wide
              // default. Users who want to see their background more clearly
              // can dial this down (0 = sharp).
              .blur(radius: preset?.backgroundBlurRadius ?? globalSettings.backgroundBlurRadius)
              .opacity(0.6)
              .clipped()
              .overlay(
                Color.black.opacity(0.15)
              )
          }
          // Layer 2: Shared accent gradient — matches Quick Mix so the
          // default preset, custom accent presets, solo mode, and Quick Mix
          // all read as variants of the same surface.
          else {
            SoundSurfaceBackground(
              accent: isSolo
                ? (globalSettings.customAccentColor ?? .accentColor)
                : (preset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
            )
          }
        }
        .accessibilityHidden(true)
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
