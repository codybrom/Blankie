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
  /// Tapping the bar steps one level toward what's playing: from the iPhone
  /// Library it shows the mixer, from the mixer it expands the full Now
  /// Playing cover. Play/pause stays inline.
  struct NowPlayingBar: View {
    /// True when the tap shows the mixer rather than expanding the player —
    /// only affects the announced hint; the owner supplies the action itself.
    var showsMixer = false
    let onTap: () -> Void

    @State private var audioManager = AudioManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var timerManager = TimerManager.shared
    @State private var globalSettings = GlobalSettings.shared
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
        openButton
        playPauseButton
      }
      #if os(iOS)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      #endif
    }

    /// The glass capsule: the open button fills the leading side, with the
    /// system AirPlay route picker as its own control at the trailing end.
    private var openButton: some View {
      HStack(spacing: 0) {
        Button {
          onTap()
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
        .accessibilityHint(showsMixer ? Text("Shows the mixer") : Text("Opens the full player"))

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
          // Match the library/Now Playing artwork tint: the active preset's
          // accent, falling back to the app accent (themingPreset is nil during
          // solo / Quick Mix, so those correctly use the app accent).
          accentColor: presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor,
          playingIcons: audioManager.playingSoundIcons(),
          isDefaultPreset: presetManager.currentPreset?.isDefault ?? true
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
    let playingIcons: [String]
    let isDefaultPreset: Bool

    static func == (lhs: ArtworkProperties, rhs: ArtworkProperties) -> Bool {
      lhs.timerActive == rhs.timerActive && lhs.soloSound?.id == rhs.soloSound?.id
        && lhs.hasSelectedSounds == rhs.hasSelectedSounds && lhs.isQuickMix == rhs.isQuickMix
        && lhs.presetArtworkId == rhs.presetArtworkId
        && lhs.animatedArtwork == rhs.animatedArtwork
        && lhs.playingIcons == rhs.playingIcons
        && lhs.isDefaultPreset == rhs.isDefaultPreset
    }
  }

  // MARK: - Preset Artwork Loader

  private struct PresetArtworkLoader: View {
    let properties: ArtworkProperties

    @State private var artworkImage: UIImage?
    @State private var presetManager = PresetManager.shared

    var body: some View {
      Group {
        if let soloSound = properties.soloSound {
          FallbackArtwork(
            glyph: .symbol(soloSound.systemIconName),
            accent: properties.accentColor ?? .accentColor,
            size: 36, cornerRadius: 4, glyphFraction: 0.44)
        } else if !properties.hasSelectedSounds && !properties.isQuickMix {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.2))
            .overlay {
              Image(systemName: "speaker.slash.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }
        } else if let image = artworkImage {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          // Quick Mix → grid, All Blankie Sounds → the Blankie mark, a custom
          // preset → a montage of its sounds; matching the preset's library tile.
          FallbackArtwork(
            glyph: .playback(
              isQuickMix: properties.isQuickMix,
              isDefaultPreset: properties.isDefaultPreset,
              icons: properties.playingIcons),
            accent: properties.accentColor ?? .accentColor,
            size: 36, cornerRadius: 4, glyphFraction: 0.5)
        }
      }
      .frame(width: 36, height: 36)
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
    NowPlayingBar {}
      .padding(.horizontal, 16)
  }

#endif
