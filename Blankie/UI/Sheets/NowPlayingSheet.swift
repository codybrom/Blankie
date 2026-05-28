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
    @Binding var showingTimer: Bool
    @Binding var presetToEdit: Preset?
    @Binding var soundToEdit: Sound?
    @Binding var showingQuickMixEditor: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var timerManager = TimerManager.shared

    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var backgroundImage: UIImage?
    @State private var currentPage: NowPlayingPage = .nowPlaying
    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0
    @State private var favoriteHapticTrigger = 0

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
                  accentColor.opacity(0.6),
                  accentColor.opacity(0.3),
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
      // Cap by height too. When the pane is short relative to its width — iPad
      // landscape with the sidebar open makes the detail pane nearly square —
      // width - 64 overflows vertically and crowds the controls. Reserve room
      // for the progress/volume stack; true (tall) portrait is unaffected.
      let artworkSize = max(min(size.width - 64, size.height - 240), 120)

      VStack(spacing: 0) {
        Spacer()

        artworkView(size: artworkSize)
          .padding(.horizontal, 32)
          .contentShape(Rectangle())
          .onTapGesture { audioManager.togglePlayback() }

        Spacer()

        soloProgressBar

        Spacer()
          .frame(maxHeight: 32)

        actionsRow

        Spacer()
          .frame(maxHeight: 16)

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
            .contentShape(Rectangle())
            .onTapGesture { audioManager.togglePlayback() }
          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 16)

        // Controls on the right
        VStack(spacing: 0) {
          Spacer()

          soloProgressBar

          Spacer()
            .frame(maxHeight: 20)

          actionsRow

          Spacer()
            .frame(maxHeight: 16)

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
        // Solo has no preset artwork: use the same placeholder card as a
        // no-artwork preset, but with the sound's own icon and the app accent.
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(0.1))
          .frame(width: size, height: size)
          .overlay {
            Image(systemName: soloSound.systemIconName)
              .font(.system(size: size * 0.35))
              .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
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
      if let soloSound = audioManager.soloModeSound, let duration = soloSound.duration,
        duration > 0
      {
        // Drive progress from the player's live `currentTime` (matching the
        // grid's ProgressBorderView). Only tick while playing — when paused the
        // playhead is stationary, so render once instead of redrawing 30×/sec.
        if audioManager.isGloballyPlaying {
          TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            soloBar(soloSound, duration: duration)
          }
        } else {
          soloBar(soloSound, duration: duration)
        }
      }
    }

    @ViewBuilder
    private func soloBar(_ soloSound: Sound, duration: TimeInterval) -> some View {
      let elapsed = soloSound.player?.currentTime ?? 0
      let progress = min(max(elapsed / duration, 0), 1)

      VStack(spacing: 8) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(.white.opacity(0.3))
              .frame(height: 4)
            Capsule()
              .fill(.white)
              .frame(width: geo.size.width * progress, height: 4)
          }
        }
        .frame(height: 4)

        HStack {
          Text(formatTime(elapsed))
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

    // MARK: - Actions Row

    /// Accent used throughout Now Playing. Solo mode is its own thing, so it
    /// uses the app accent instead of carrying over the last preset's accent.
    private var accentColor: Color {
      if audioManager.soloModeSound != nil {
        return globalSettings.customAccentColor ?? .accentColor
      }
      return presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
        ?? .accentColor
    }

    /// Starred token for the current context, or nil when favoriting doesn't
    /// apply. Solo sounds favorite under their `solo:` token; the default preset
    /// maps to `allSoundsToken`, custom presets to their UUID. Quick Mix isn't
    /// favoritable, so it returns nil (the star is hidden).
    private var favoriteToken: String? {
      if let solo = audioManager.soloModeSound {
        return GlobalSettings.soloToken(forFileName: solo.fileName)
      }
      guard !audioManager.isQuickMix, let preset = presetManager.currentPreset else { return nil }
      return preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
    }

    /// Whether the row has something to edit: a solo sound, a preset, or Quick
    /// Mix.
    private var canEditCurrent: Bool {
      audioManager.soloModeSound != nil || audioManager.isQuickMix
        || presetManager.currentPreset != nil
    }

    /// Favorite / Timer / Edit controls shown above the volume slider. Favorite
    /// and Edit drop out in contexts where they don't apply, so the row may show
    /// one to three buttons; it stays centered either way.
    @ViewBuilder
    private var actionsRow: some View {
      HStack(spacing: 44) {
        if let token = favoriteToken {
          let starred = globalSettings.isStarred(token)
          Button {
            globalSettings.toggleStarred(token)
            favoriteHapticTrigger += 1
          } label: {
            Image(systemName: starred ? "star.fill" : "star")
              .foregroundColor(starred ? accentColor : .white.opacity(0.7))
          }
          .accessibilityLabel(starred ? Text("Unfavorite") : Text("Favorite"))
        }

        Button {
          showingTimer = true
        } label: {
          Image(systemName: "timer")
            .foregroundColor(timerManager.isTimerActive ? accentColor : .white.opacity(0.7))
        }
        .accessibilityLabel(Text("Timer"))

        if canEditCurrent {
          Button {
            if let solo = audioManager.soloModeSound {
              soundToEdit = solo
            } else if audioManager.isQuickMix {
              showingQuickMixEditor = true
            } else if let preset = presetManager.currentPreset {
              presetToEdit = preset
            }
          } label: {
            Image(
              systemName: audioManager.soloModeSound != nil
                ? "slider.horizontal.3" : "slider.vertical.3"
            )
            .foregroundColor(.white.opacity(0.7))
          }
          .accessibilityLabel(
            audioManager.soloModeSound != nil
              ? Text("Edit Sound")
              : (audioManager.isQuickMix ? Text("Edit Quick Mix") : Text("Edit Preset")))
        }
      }
      .font(.system(size: 22))
      .buttonStyle(.plain)
      // Fire only on the user's own tap of the star — not when the favorite
      // state changes because the preset switched or another surface toggled it.
      .sensoryFeedback(.selection, trigger: favoriteHapticTrigger)
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
    NowPlayingSheet(
      showingPresetPicker: .constant(false),
      showingTimer: .constant(false),
      presetToEdit: .constant(nil),
      soundToEdit: .constant(nil),
      showingQuickMixEditor: .constant(false)
    )
  }

#endif
