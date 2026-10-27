//
//  MixerView+Helpers.swift
//  Blankie
//
//  Created by Cody Bromley on 2/22/26.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension MixerView {
    var filteredSounds: [Sound] {
      audioManager.orderedVisibleSounds(for: presetManager.currentPreset)
    }

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
      // Solo uses the app accent gradient, like Quick Mix, and ignores preset artwork.
      let isSolo = audioManager.soloModeSound != nil

      GeometryReader { geometry in
        ZStack {
          if !isSolo, preset != nil,
            let artworkImage = backgroundImage
          {
            Image(uiImage: artworkImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .blur(radius: globalSettings.backgroundBlurRadius)
              .opacity(0.6)
              .clipped()
              .overlay(
                Color.black.opacity(0.15)
              )
              // Distinct identity per image so artwork swaps crossfade.
              .id(ObjectIdentifier(artworkImage))
              .transition(.opacity)
          }
          else {
            SoundSurfaceBackground(
              accent: isSolo
                ? (globalSettings.customAccentColor ?? .accentColor)
                : (preset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
            )
            .transition(.opacity)
          }
        }
        // Gradient and artwork crossfade on isSolo; artwork swaps animate in the task below.
        .animation(.easeInOut(duration: 0.35), value: isSolo)
        .accessibilityHidden(true)
      }
      .ignoresSafeArea()
      .task(
        id:
          "\(preset?.id.uuidString ?? "")-\(preset?.artworkId?.uuidString ?? "")-\(preset?.animatedArtwork?.previewPath ?? "")"
      ) {
        guard let preset = preset else {
          withAnimation(.easeInOut(duration: 0.35)) { backgroundImage = nil }
          return
        }
        // Keep the old image until the next loads, then crossfade to it.
        let loaded = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
        withAnimation(.easeInOut(duration: 0.35)) { backgroundImage = loaded }
      }
    }
  }

  /// Shared background used by both the main tile grid (non-artwork presets)
  /// and Quick Mix so the two modes read as one visual system.
  struct SoundSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    var body: some View {
      // Tile text is `.primary`, so the base stop follows the color scheme.
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
