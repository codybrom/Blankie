//
//  NowPlayingSheet.swift
//  Blankie
//
//  Apple Music-inspired Now Playing view with animated background
//

import SwiftUI

#if os(iOS) || os(visionOS)

  enum NowPlayingPage: Int {
    case nowPlaying = 0
    case mixer = 1
  }

  struct NowPlayingSheet: View {
    var onDismiss: (() -> Void)?
    @Binding var showingPresetPicker: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared

    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var backgroundImage: UIImage?
    @State private var currentPage: NowPlayingPage = .nowPlaying
    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0

    private var artworkTaskID: String {
      let solo = audioManager.soloModeSound?.id.uuidString ?? ""
      let preset = presetManager.currentPreset?.id.uuidString ?? ""
      return "\(solo)-\(preset)"
    }

    var body: some View {
      GeometryReader { geometry in
        let size = geometry.size
        let safeArea = geometry.safeAreaInsets

        // Background with blurred artwork or gradient
        Color.black
          .overlay {
            if let image = backgroundImage {
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: size.width, minHeight: size.height)
                .clipped()
                .blur(radius: 40)
                .opacity(0.4)
            } else {
              LinearGradient(
                colors: [
                  (presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                    ?? .accentColor).opacity(0.6),
                  (presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                    ?? .accentColor).opacity(0.3),
                  Color.black.opacity(0.8),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            }
          }
          .ignoresSafeArea()
          .overlay {
            expandedPlayerView(size, safeArea)
          }
          .task(id: artworkTaskID) {
            if audioManager.soloModeSound == nil, let preset = presetManager.currentPreset {
              backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(
                for: preset)
            } else if audioManager.soloModeSound != nil {
              backgroundImage = nil
            }
          }
          .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: currentPage)
      }
    }

    // MARK: - Now Playing View

    @ViewBuilder
    private func nowPlayingView(in size: CGSize) -> some View {
      // Only use the side-by-side landscape layout when the available area
      // is meaningfully wider than tall. On iPad with the sidebar visible
      // the detail pane can end up nearly square, which makes the HStack
      // artwork+controls layout cramped — fall back to stacked portrait.
      let aspect = size.height > 0 ? size.width / size.height : 1
      if aspect > 1.6 {
        landscapeNowPlaying(in: size)
      } else {
        portraitNowPlaying(in: size)
      }
    }

    // MARK: - Portrait Layout

    @ViewBuilder
    private func portraitNowPlaying(in size: CGSize) -> some View {
      let artworkSize = size.width - 64

      VStack(spacing: 0) {
        Spacer()

        artworkView(size: artworkSize)
          .padding(.horizontal, 32)

        Spacer()

        soloProgressBar

        Spacer()
          .frame(maxHeight: 40)

        volumeSlider

        Spacer()
      }
    }

    // MARK: - Landscape Layout

    @ViewBuilder
    private func landscapeNowPlaying(in size: CGSize) -> some View {
      let artworkSize = max(size.height * 0.75, 120)

      HStack(spacing: 0) {
        // Artwork takes the left side, vertically centered. Leading padding
        // keeps it off the sidebar divider on iPad.
        VStack {
          Spacer()
          artworkView(size: artworkSize)
          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 16)

        // Controls on the right
        VStack(spacing: 0) {
          Spacer()

          soloProgressBar

          Spacer()
            .frame(maxHeight: 24)

          volumeSlider

          Spacer()
        }
        .frame(width: size.width * 0.4)
        .padding(.trailing, 16)
      }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
      if let soloSound = audioManager.soloModeSound {
        Circle()
          .fill(Color.white.opacity(0.1))
          .frame(width: size, height: size)
          .overlay {
            Image(systemName: soloSound.systemIconName)
              .font(.system(size: size * 0.35))
              .foregroundColor(
                presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                  ?? .accentColor)
          }
          .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
      } else if let image = backgroundImage {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(0.1))
          .frame(width: size, height: size)
          .overlay {
            BrandedBlankieIcon(
              size: size * 0.35,
              color: presetManager.currentPreset?.accentColor
            )
          }
      }
    }

    @ViewBuilder
    private var soloProgressBar: some View {
      if let soloSound = audioManager.soloModeSound, let duration = soloSound.duration {
        VStack(spacing: 8) {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(.white.opacity(0.3))
                .frame(height: 4)
              Capsule()
                .fill(.white)
                .frame(width: geo.size.width * soloSound.playbackProgress, height: 4)
            }
          }
          .frame(height: 4)

          HStack {
            Text(formatTime(duration * soloSound.playbackProgress))
              .font(.caption2)
              .foregroundColor(.white.opacity(0.7))
              .monospacedDigit()
            Spacer()
            Text(formatTime(duration))
              .font(.caption2)
              .foregroundColor(.white.opacity(0.7))
              .monospacedDigit()
          }
        }
        .padding(.horizontal, 32)
      }
    }

    private var volumeSlider: some View {
      HStack(spacing: 15) {
        Image(systemName: "speaker.fill")
          .foregroundColor(.gray)
          .font(.caption)

        Slider(
          value: Binding(
            get: { globalSettings.volume },
            set: { globalSettings.setVolume($0) }
          ),
          in: 0...1,
          onEditingChanged: { editing in
            withAnimation(.easeOut(duration: 0.2)) {
              isEditingVolume = editing
            }
          }
        )
        .tint(.white.opacity(0.7))
        .sliderThumbVisibility(isEditingVolume ? .visible : .hidden)

        Image(systemName: "speaker.wave.3.fill")
          .foregroundColor(.gray)
          .font(.caption)
      }
      .padding(.horizontal, 32)
    }

    // MARK: - Expanded Player View

    @ViewBuilder
    private func expandedPlayerView(_ size: CGSize, _: EdgeInsets) -> some View {
      nowPlayingView(in: size)
    }

    // MARK: - Helper Methods

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      let minutes = Int(timeInterval) / 60
      let seconds = Int(timeInterval) % 60
      return String(format: "%d:%02d", minutes, seconds)
    }

  }

  #Preview {
    NowPlayingSheet(showingPresetPicker: .constant(false))
  }

#endif
