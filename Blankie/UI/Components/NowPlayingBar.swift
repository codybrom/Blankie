//
//  NowPlayingBar.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//
//  Apple Music-style mini player bar that expands into the Now Playing cover.
//

import SwiftUI

#if os(iOS) || os(visionOS)

  /// Compact glass bar pinned above the bottom safe area on iPhone and iPad.
  /// Tapping the bar opens the full Now Playing cover; play/pause stays inline.
  struct NowPlayingBar: View {
    @Binding var expandPlayer: Bool

    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var playPauseTrigger = 0

    var body: some View {
      GlassEffectContainer(spacing: 12) {
        barContent
      }
    }

    /// Capsule bar plus a standalone play/pause circle trailing it, so the two
    /// glass shapes read as separate controls that share one glass tissue.
    private var barContent: some View {
      HStack(spacing: 12) {
        expandButton
        playPauseButton
      }
      #if os(iOS)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      #endif
    }

    /// The glass capsule: the expand button fills the leading side, with the
    /// system AirPlay route picker as its own control at the trailing end.
    private var expandButton: some View {
      HStack(spacing: 0) {
        Button {
          expandPlayer = true
        } label: {
          HStack(spacing: 10) {
            artworkView
            infoView
            Spacer(minLength: 0)
          }
          .padding(.leading, 12)
          .frame(height: 58)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Now Playing"))
        .accessibilityHint(Text("Opens the full player"))

        #if os(iOS)
          AirPlayRouteButton(
            activeColor: accentColor,
            inactiveColor: Color(.secondaryLabel)
          )
          .frame(width: 44, height: 44)
          .accessibilityLabel(Text("AirPlay"))
          .padding(.trailing, 6)
        #endif
      }
      .modifier(NowPlayingBarGlass())
    }

    // MARK: - Artwork

    private var artworkView: some View {
      PresetArtworkLoader(
        properties: ArtworkProperties(
          timerActive: timerManager.isTimerActive,
          soloSound: audioManager.soloModeSound,
          hasSelectedSounds: audioManager.hasSelectedSounds,
          isQuickMix: audioManager.isQuickMix,
          presetArtworkId: presetManager.currentPreset?.artworkId,
          animatedArtwork: presetManager.currentPreset?.animatedArtwork,
          accentColor: globalSettings.customAccentColor
        )
      )
      .accessibilityHidden(true)
    }

    // MARK: - Title / Status

    private var infoView: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
        if let caption {
          Text(caption)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }

    private var title: String {
      if let soloSound = audioManager.soloModeSound {
        return soloSound.title
      }
      if audioManager.isQuickMix {
        return String(localized: "Quick Mix")
      }
      return presetManager.currentPreset?.activeTitle ?? "Blankie"
    }

    /// Status line under the title. Active playback shows no caption — the
    /// title alone reads cleaner than announcing "Playing".
    private var caption: String? {
      if audioManager.soloModeSound == nil && !audioManager.hasSelectedSounds
        && !audioManager.isQuickMix
      {
        return String(localized: "No sounds selected")
      }
      if timerManager.isTimerActive {
        return timerCaption
      }
      if !audioManager.isGloballyPlaying {
        return String(localized: "Paused")
      }
      return nil
    }

    /// Timer status mirroring the mixer's top-bar caption: a countdown inside
    /// the final minute, the clock end time otherwise.
    private var timerCaption: String {
      if timerManager.remainingTime < 60 {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.second]
        return String(
          localized:
            "Pausing in \(formatter.string(from: timerManager.remainingTime) ?? "0 seconds")"
        )
      }
      let endTime = timerManager.getEndTime() ?? Date()
      return String(localized: "Pausing at \(endTime.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - Play / Pause

    private var accentColor: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    private var playPauseButton: some View {
      // Pause must always be reachable: enable whenever the app is playing OR
      // has sounds to start, matching every other surface's convention so the
      // bar can never get stuck in a "playing" state with no way to pause.
      let isInteractive = audioManager.isGloballyPlaying || audioManager.hasSelectedSounds
      return Button {
        guard isInteractive else { return }
        playPauseTrigger += 1
        audioManager.togglePlayback()
      } label: {
        Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 26))
          .foregroundColor(isInteractive ? accentColor : .secondary)
          .contentTransition(
            .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
          )
          .offset(x: audioManager.isGloballyPlaying ? 0 : 1)
          .frame(width: 68, height: 68)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(!isInteractive)
      .sensoryFeedback(.selection, trigger: playPauseTrigger)
      .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))
      .modifier(NowPlayingCircleGlass())
    }
  }

  // MARK: - Glass Treatment

  /// Liquid Glass capsule
  private struct NowPlayingBarGlass: ViewModifier {
    func body(content: Content) -> some View {
      content.glassEffect(.regular.interactive(), in: .capsule)
    }
  }

  /// Circle variant for the standalone play/pause control.
  private struct NowPlayingCircleGlass: ViewModifier {
    func body(content: Content) -> some View {
      content.glassEffect(.regular.interactive(), in: .circle)
    }
  }

  // MARK: - Artwork Properties

  /// Equatable snapshot of everything that affects the bar's artwork slot, so
  /// the async loader task only restarts when something it shows has changed.
  struct ArtworkProperties: Equatable {
    let timerActive: Bool
    let soloSound: Sound?
    let hasSelectedSounds: Bool
    let isQuickMix: Bool
    let presetArtworkId: UUID?
    let animatedArtwork: AnimatedArtworkRef?
    let accentColor: Color?

    static func == (lhs: ArtworkProperties, rhs: ArtworkProperties) -> Bool {
      lhs.timerActive == rhs.timerActive && lhs.soloSound?.id == rhs.soloSound?.id
        && lhs.hasSelectedSounds == rhs.hasSelectedSounds && lhs.isQuickMix == rhs.isQuickMix
        && lhs.presetArtworkId == rhs.presetArtworkId
        && lhs.animatedArtwork == rhs.animatedArtwork
    }
  }

  // MARK: - Preset Artwork Loader

  private struct PresetArtworkLoader: View {
    let properties: ArtworkProperties

    @State private var artworkImage: UIImage?
    @StateObject private var presetManager = PresetManager.shared

    var body: some View {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.secondary.opacity(0.2))
        .frame(width: 36, height: 36)
        .overlay {
          if let soloSound = properties.soloSound {
            Image(systemName: soloSound.systemIconName)
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(properties.accentColor ?? .accentColor)
          } else if !properties.hasSelectedSounds && !properties.isQuickMix {
            Image(systemName: "speaker.slash.fill")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.secondary)
          } else if let image = artworkImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            Image(systemName: "waveform")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(
          id:
            "\(properties.presetArtworkId?.uuidString ?? "nil")-\(properties.animatedArtwork?.squarePreviewPath ?? properties.animatedArtwork?.previewPath ?? "nil")"
        ) {
          // Only load artwork when not in solo/no sounds mode
          guard properties.soloSound == nil, properties.hasSelectedSounds || properties.isQuickMix
          else {
            artworkImage = nil
            return
          }

          // Try to load from artworkId first
          if let artworkId = properties.presetArtworkId,
            let data = await PresetArtworkManager.shared.loadArtworkData(id: artworkId),
            let image = UIImage(data: data)
          {
            artworkImage = image
          } else if let preset = presetManager.currentPreset {
            // Fallback: Use animated artwork preview if available
            artworkImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
          } else {
            artworkImage = nil
          }
        }
    }
  }

  #Preview {
    NowPlayingBar(expandPlayer: .constant(false))
      .padding(.horizontal, 16)
  }

#endif
