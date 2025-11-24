//
//  NowPlayingAccessoryView.swift
//  Blankie
//
//  Tab view bottom accessory for Now Playing
//

import SwiftUI

#if os(iOS) || os(visionOS)

  struct NowPlayingAccessoryView: View {
    @Binding var expandPlayer: Bool

    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared

    @State private var backgroundImage: UIImage?

    var body: some View {
      // Mini player bar (always shown in accessory above tab bar)
      Button {
        // Tapping opens fullscreen player
        expandPlayer = true
      } label: {
        HStack(spacing: 12) {
          // Artwork thumbnail or sound icon
          Group {
            if let soloSound = audioManager.soloModeSound {
              // Solo mode: show sound icon
              Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay {
                  Image(systemName: soloSound.systemIconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
                }
            } else if let image = backgroundImage {
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
              Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                  BrandedBlankieIcon(size: 18)
                }
            }
          }

          // Now playing info
          VStack(alignment: .leading, spacing: 2) {
            if let soloSound = audioManager.soloModeSound {
              Text(soloSound.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
              Text("Solo Mode")
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
              Text(presetManager.currentPreset?.activeTitle ?? "Blankie")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
              if audioManager.hasSelectedSounds {
                let soundCount = audioManager.sounds.filter { $0.isSelected }.count
                Text("\(soundCount) sound\(soundCount == 1 ? "" : "s")")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              } else {
                Text("No sounds")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Spacer(minLength: 0)

          // Control buttons
          Group {
            Button {
              if audioManager.hasSelectedSounds {
                audioManager.togglePlayback()
              }
            } label: {
              Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(!audioManager.hasSelectedSounds)

            Button {
              // Next action
            } label: {
              Image(systemName: "forward.fill")
            }
          }
          .font(.title3)
          .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 10)
        .frame(height: 70)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .task {
        // Load background image
        if let preset = presetManager.currentPreset {
          backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
        }
      }
    }
  }

#endif
