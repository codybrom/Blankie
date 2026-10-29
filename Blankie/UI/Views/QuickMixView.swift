//
//  QuickMixView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct QuickMixView: View {
    /// Regular width: Quick Mix has no playback bar, so its controls sit in a
    /// column beside the tiles. Tapping the artwork opens Now Playing.
    var onOpenNowPlaying: (() -> Void)?
    /// Where Now Playing zooms from: the column's artwork, or the bar.
    var nowPlayingZoom: Namespace.ID?
    /// Whether the control column (which names Quick Mix) is on screen.
    var onColumnChange: ((Bool) -> Void)?
    var columns = 2

    @State private var size: CGSize = .zero
    @State private var fold = FoldInfo.none

    /// On iPhone Duo the column fills the page left of the fold.
    private var foldPage: CGFloat? {
      CreaseInsets.leadingPage(containerWidth: size.width, fold: fold)
    }

    /// The column needs room both ways (a large iPhone in landscape is wide but
    /// short). Otherwise it's the same bare bar as a preset page.
    private var showsColumn: Bool { size.width >= 640 && size.height >= 520 }

    let audioManager = AudioManager.shared
    let globalSettings = GlobalSettings.shared

    private var quickMixSounds: [Sound] {
      return globalSettings.quickMixSoundFileNames.compactMap { fileName in
        audioManager.sounds.first { $0.fileName == fileName && !$0.isPresetUseOnly }
      }
    }

    var body: some View {
      ZStack {
        // The same accent gradient as the main mixer, so Quick Mix matches it.
        SoundSurfaceBackground(
          accent: globalSettings.customAccentColor ?? .accentColor
        )

        HStack(spacing: 0) {
          if let onOpenNowPlaying, showsColumn {
            QuickMixControlColumn(onOpenNowPlaying: onOpenNowPlaying, zoom: nowPlayingZoom)
              .frame(width: foldPage ?? 240)
            if foldPage != nil {
              Color.clear.frame(width: fold.frame.width)
            }
          }
          grid
        }
        // No room for the column (iPad portrait beside the sidebar, a large
        // iPhone in landscape): the same bare bar as a preset page.
        .safeAreaInset(edge: .bottom) {
          if let onOpenNowPlaying, size.width > 0, !showsColumn {
            NowPlayingBar(style: .bare, onTap: onOpenNowPlaying)
              .modifier(NowPlayingZoomSource(namespace: nowPlayingZoom))
              .padding(.horizontal, 16)
          }
        }
      }
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: {
        size = $0
      }
      .onFoldChange { fold = $0 }
      .onChange(of: onOpenNowPlaying != nil && showsColumn, initial: true) { _, shown in
        onColumnChange?(shown)
      }
    }

    private var grid: some View {
      SoundGridView(
        sounds: quickMixSounds,
        onMove: { from, to in
          var ordered = quickMixSounds.map(\.fileName)
          ordered.move(fromOffsets: from, toOffset: to)
          // Carry over stored names that didn't resolve to a displayed sound
          // (e.g. a renamed built-in), so a reorder never prunes them.
          let shown = Set(ordered)
          ordered.append(
            contentsOf: globalSettings.quickMixSoundFileNames.filter { !shown.contains($0) })
          globalSettings.setQuickMixSoundFileNames(ordered)
        },
        tile: { sound in
          GridSoundButton(
            sound: sound,
            isActive: audioManager.isQuickMix && sound.isSelected,
            onTap: {
              audioManager.leaveUnsavedMixAsking {
                if !audioManager.isQuickMix {
                  audioManager.enterQuickMix()
                }
                audioManager.toggleQuickMixSound(sound)
              }
            }
          )
        },
        columns: columns
      )
    }
  }

  /// Quick Mix's own transport for regular width: artwork (opens Now Playing),
  /// title, play/pause, volume, AirPlay and Timer.
  private struct QuickMixControlColumn: View {
    let onOpenNowPlaying: () -> Void
    let zoom: Namespace.ID?

    @State private var audioManager = AudioManager.shared
    @State private var globalSettings = GlobalSettings.shared
    @State private var timerManager = TimerManager.shared
    @State private var showingTimer = false

    private var accent: Color { globalSettings.customAccentColor ?? .accentColor }

    var body: some View {
      VStack(spacing: 22) {
        Spacer(minLength: 12)
        Button(action: onOpenNowPlaying) {
          FallbackArtwork(
            glyph: .playback(isQuickMix: true, isDefaultPreset: false, icons: []),
            accent: accent, size: 160, glyphFraction: 0.5)
        }
        .buttonStyle(.plain)
        .modifier(NowPlayingZoomSource(namespace: zoom))
        .accessibilityLabel(Text("Now Playing"))
        .accessibilityHint(Text("Opens the full player"))

        Text("Quick Mix")
          .font(.title2.bold())

        // No previous/next: Quick Mix isn't part of the favorites cycle.
        Button {
          audioManager.togglePlayback()
        } label: {
          Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 36))
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(!audioManager.isGloballyPlaying && !audioManager.hasSelectedSounds)
        .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))

        // CarPlay owns the volume while connected, like Now Playing.
        if !audioManager.isCarPlayConnected {
          volume
        }

        HStack(spacing: 16) {
          #if os(iOS)
            AirPlayRouteButton(activeColor: accent, inactiveColor: Color(.secondaryLabel))
              .frame(width: 44, height: 44)
              .accessibilityLabel(Text("AirPlay"))
          #endif
          Button {
            showingTimer = true
          } label: {
            Image(systemName: "timer")
              .font(.system(size: 20))
              .foregroundStyle(timerManager.isTimerActive ? accent : Color.primary)
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Timer"))
        }
        Spacer(minLength: 12)
      }
      .padding(.horizontal, 20)
      .sheet(isPresented: $showingTimer) {
        TimerSheetView()
          .presentationSizing(.form)
      }
    }

    /// Same source as Now Playing's volume row.
    @ViewBuilder
    private var volume: some View {
      #if os(iOS)
        if globalSettings.mixWithOthers {
          Slider(
            value: Binding(
              get: { globalSettings.volumeWithOtherAudio },
              set: { globalSettings.setVolumeWithOtherAudio($0) }
            ),
            in: 0...1
          )
          .tint(accent)
          .accessibilityLabel(Text("Blankie Volume with Media"))
        } else {
          SystemVolumeSlider()
            .frame(height: 30)
            .accessibilityLabel(Text("Volume"))
        }
      #endif
    }
  }

  private struct NowPlayingZoomSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
      if let namespace {
        content.matchedTransitionSource(id: "nowPlaying", in: namespace)
      } else {
        content
      }
    }
  }

  #Preview {
    QuickMixView()
  }
#endif
