//
//  MixerView+UIComponents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  import TipKit

  // MARK: - UI Components Extension

  extension MixerView {
    // MARK: - Navigation Elements

    var navigationTitle: String {
      if let soloSound = audioManager.soloModeSound {
        return soloSound.title
      }

      if audioManager.isQuickMix {
        return "Quick Mix"
      }

      if let preset = presetManager.currentPreset {
        return preset.isDefault ? "Blankie" : preset.name
      }

      return "Blankie"
    }

    var presetButton: some View {
      Button(action: {
        showingPresetPicker = true
      }) {
        HStack(spacing: 4) {
          if audioManager.soloModeSound != nil {
            Image(systemName: "headphones.circle.fill")
              .foregroundColor(
                presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                  ?? .accentColor)
          } else if audioManager.isQuickMix {
            Image(systemName: "square.grid.2x2.fill")
              .foregroundColor(
                presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                  ?? .accentColor)
          }
          Text(navigationTitle)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
          Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .sensoryFeedback(.selection, trigger: showingPresetPicker)
    }

    // MARK: - Toolbar Components

    var bottomToolbar: some View {
      Group {
        if #available(iOS 26.0, *) {
          GlassEffectContainer(spacing: 8) {
            bottomToolbarContent
          }
          .padding(.bottom, 4)
        } else {
          bottomToolbarContent
            .padding(.bottom, 4)
        }
      }
      .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    var bottomToolbarContent: some View {
      VStack(spacing: 8) {
        // 3-Button Toolbar with connected glass tissue
        if #available(iOS 26.0, *) {
          GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
              // Left button
              if audioManager.soloModeSound != nil || audioManager.isQuickMix {
                Button {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    if audioManager.soloModeSound != nil {
                      audioManager.exitSoloMode()
                    } else if audioManager.isQuickMix {
                      audioManager.exitQuickMix()
                    }
                  }
                } label: {
                  Image(systemName: "arrow.backward")
                    .font(.system(size: 22))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
                }
                .accessibilityLabel("Back")
                .buttonStyle(.plain)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
              } else {
                Button {
                  withAnimation(.easeInOut(duration: 0.3)) {
                    showingNowPlaying.toggle()
                  }
                } label: {
                  Image(systemName: showingNowPlaying ? "list.bullet" : "music.note.list")
                    .font(.system(size: 22))
                    .foregroundColor(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                }
                .accessibilityLabel(showingNowPlaying ? Text("Hide Now Playing") : Text("Show Now Playing"))
                .buttonStyle(.plain)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
              }

              // Play/Pause button (always visible)
              playPauseButton

              // Right button (always settings)
              menuButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
              Capsule(style: .continuous)
                .fill(.clear)
            }
          }
        } else {
          // Fallback for iOS 25 and earlier
          HStack(spacing: 20) {
            // Left button
            if audioManager.soloModeSound != nil || audioManager.isQuickMix {
              Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                  if audioManager.soloModeSound != nil {
                    audioManager.exitSoloMode()
                  } else if audioManager.isQuickMix {
                    audioManager.exitQuickMix()
                  }
                }
              } label: {
                Image(systemName: "arrow.backward")
                  .font(.system(size: 22))
                  .foregroundColor(.primary)
                  .frame(width: 56, height: 56)
              }
              .accessibilityLabel("Back")
              .buttonStyle(.plain)
              .contentShape(Circle())
              .modernGlassEffect(cornerRadius: 28)
            } else {
              Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                  showingNowPlaying.toggle()
                }
              } label: {
                Image(systemName: showingNowPlaying ? "list.bullet" : "music.note.list")
                  .font(.system(size: 22))
                  .foregroundColor(.primary)
                  .frame(width: 56, height: 56)
              }
              .accessibilityLabel(showingNowPlaying ? Text("Hide Now Playing") : Text("Show Now Playing"))
              .buttonStyle(.plain)
              .contentShape(Circle())
              .modernGlassEffect(cornerRadius: 28)
            }

            // Play/Pause button (always visible)
            playPauseButton

            // Right button (always settings)
            menuButton
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .modernGlassEffect(cornerRadius: 40)
        }
      }
    }

    var playPauseButton: some View {
      let button = Button(action: {
        if audioManager.hasSelectedSounds {
          playPauseTrigger += 1
          audioManager.togglePlayback()
        }
      }) {
        Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 26))
          .foregroundColor(
            audioManager.hasSelectedSounds
              ? (presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor
                ?? .accentColor)
              : .secondary
          )
          .contentTransition(
            .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
          )
          .offset(x: audioManager.isGloballyPlaying ? 0 : 1)
          .frame(width: 68, height: 68)
          .contentShape(Circle())
      }
      .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))

      if #available(iOS 26.0, *) {
        return
          button
          .glassEffect(.regular.interactive(), in: .circle)
          .disabled(!audioManager.hasSelectedSounds)
          .sensoryFeedback(.selection, trigger: playPauseTrigger)
          .onLongPressGesture { showingPresetPicker = true }
      } else {
        return
          button
          .modernGlassEffect(cornerRadius: 34)
          .disabled(!audioManager.hasSelectedSounds)
          .sensoryFeedback(.selection, trigger: playPauseTrigger)
          .onLongPressGesture { showingPresetPicker = true }
      }
    }

    @ViewBuilder
    var menuButton: some View {
      // On iPad, the top nav bar has a direct Edit Preset button and the
      // sidebar has Settings, so the ellipsis menu is redundant. Collapse
      // it to a direct Timer button. iPhone keeps the full menu.
      if isLargeDevice {
        timerButton
      } else {
        iPhoneMenuButton
      }
    }

    private var iPhoneMenuButton: some View {
      let button = Menu {
        Button {
          showingSettings = true
        } label: {
          Label("Blankie Settings", systemImage: "gearshape")
        }

        Divider()

        if audioManager.isQuickMix {
          Button {
            showingQuickMixEditor = true
          } label: {
            Label("Edit Quick Mix", systemImage: "slider.vertical.3")
          }
        } else if let preset = presetManager.currentPreset {
          Button {
            presetToEdit = preset
          } label: {
            Label("Edit Preset", systemImage: "slider.vertical.3")
          }
        }

        Button {
          showingTimer = true
        } label: {
          Label(
            timerManager.isTimerActive ? "Timer (Active)" : "Timer",
            systemImage: "timer"
          )
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 22))
          .foregroundColor(.primary)
          .frame(width: 56, height: 56)
      }
      .accessibilityLabel("More Options")
      .buttonStyle(.plain)
      .contentShape(Circle())

      if #available(iOS 26.0, *) {
        return
          button
          .glassEffect(.regular.interactive(), in: .circle)
          .sensoryFeedback(.selection, trigger: menuTrigger)
      } else {
        return
          button
          .modernGlassEffect(cornerRadius: 28)
          .sensoryFeedback(.selection, trigger: menuTrigger)
      }
    }

    private var timerButton: some View {
      let button = Button {
        showingTimer = true
      } label: {
        Image(systemName: "timer")
          .font(.system(size: 22))
          .foregroundColor(timerManager.isTimerActive ? .accentColor : .primary)
          .frame(width: 56, height: 56)
      }
      .accessibilityLabel("Timer")
      .buttonStyle(.plain)
      .contentShape(Circle())

      if #available(iOS 26.0, *) {
        return
          button
          .glassEffect(.regular.interactive(), in: .circle)
          .sensoryFeedback(.selection, trigger: menuTrigger)
      } else {
        return
          button
          .modernGlassEffect(cornerRadius: 28)
          .sensoryFeedback(.selection, trigger: menuTrigger)
      }
    }

    // MARK: - Artwork Properties (shared across views)

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
  }

  // MARK: - Top Bar Glass Button

  struct TopBarGlassButton: ViewModifier {
    func body(content: Content) -> some View {
      if #available(iOS 26.0, *) {
        content
          .glassEffect(.regular.interactive(), in: .circle)
      } else {
        content
          .background(.ultraThinMaterial, in: Circle())
          .overlay(
            Circle()
              .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
          )
          .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
      }
    }
  }

  // MARK: - Liquid Glass Effect Extension

  extension View {
    @ViewBuilder
    func modernGlassEffect(cornerRadius: CGFloat = 12) -> some View {
      if #available(iOS 26.0, *) {
        self.glassEffect(
          .regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
      } else {
        background(
          .ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
      }
    }
  }

  // MARK: - Now Playing Bar Container

  private struct NowPlayingBarContainer: View {
    let editMode: EditMode
    @Binding var showingTimer: Bool
    @Binding var presetToEdit: Preset?
    @Binding var showingPresetPicker: Bool

    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared

    var body: some View {
      if editMode == .inactive && !audioManager.isQuickMix {
        unifiedNowPlayingBar
      }
    }

    @ViewBuilder
    var unifiedNowPlayingBar: some View {
      HStack(spacing: 10) {
        // Dynamic artwork based on state
        presetArtworkView()

        // Dynamic info based on state
        VStack(alignment: .leading, spacing: 2) {
          if let soloSound = audioManager.soloModeSound {
            // Solo mode
            Text(soloSound.title)
              .font(.caption)
              .fontWeight(.medium)
              .lineLimit(1)

            Text("Solo Mode")
              .font(.caption2)
              .foregroundStyle(.secondary)
          } else if !audioManager.hasSelectedSounds && !audioManager.isQuickMix {
            // No sounds selected
            Text(
              presetManager.currentPreset?.isDefault == true
                ? "Blankie" : (presetManager.currentPreset?.name ?? "Blankie")
            )
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)

            Text("No sounds selected")
              .font(.caption2)
              .foregroundStyle(.secondary)
          } else {
            // Regular playback (and timer mode uses caption)
            Text(
              presetManager.currentPreset?.isDefault == true
                ? "Blankie" : (presetManager.currentPreset?.name ?? "Blankie")
            )
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)

            // Show timer info in caption if active, otherwise show play status
            if timerManager.isTimerActive {
              if timerManager.remainingTime < 60 {
                Text("Stops in \(formatTime(timerManager.remainingTime))")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              } else {
                Text("Stops at \(formatEndTime())")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            } else {
              Text(audioManager.isGloballyPlaying ? "Playing" : "Paused")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }

        Spacer()

        // Trailing buttons (these stop tap propagation)
        HStack(spacing: 8) {
          // Timer button (shown when timer is active)
          if timerManager.isTimerActive {
            Button {
              showingTimer = true
            } label: {
              Image(systemName: "timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Timer")
            .buttonStyle(.borderless)
          }

          // Exit solo mode button (if in solo mode)
          if audioManager.soloModeSound != nil {
            Button {
              withAnimation(.easeInOut(duration: 0.3)) {
                audioManager.exitSoloMode()
              }
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Exit Solo Mode")
            .buttonStyle(.borderless)
          }

          // Edit preset button (if not in solo mode)
          if audioManager.soloModeSound == nil, let preset = presetManager.currentPreset {
            Button {
              presetToEdit = preset
            } label: {
              Image(systemName: "slider.vertical.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit Preset")
            .buttonStyle(.borderless)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .modernGlassEffect(cornerRadius: 10)
      .contentShape(Rectangle())
      .onTapGesture {
        // Tap on the main bar opens preset picker
        showingPresetPicker = true
      }
      .popoverTip(SwitchPresetsTip(), arrowEdge: .bottom)
    }

    @ViewBuilder
    func presetArtworkView() -> some View {
      let artworkProps = MixerView.ArtworkProperties(
        timerActive: timerManager.isTimerActive,
        soloSound: audioManager.soloModeSound,
        hasSelectedSounds: audioManager.hasSelectedSounds,
        isQuickMix: audioManager.isQuickMix,
        presetArtworkId: presetManager.currentPreset?.artworkId,
        animatedArtwork: presetManager.currentPreset?.animatedArtwork,
        accentColor: globalSettings.customAccentColor
      )
      PresetArtworkLoader(properties: artworkProps)
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      let formatter = DateComponentsFormatter()
      formatter.unitsStyle = .full
      formatter.allowedUnits = timeInterval >= 60 ? [.hour, .minute] : [.minute, .second]
      formatter.zeroFormattingBehavior = .dropAll
      return formatter.string(from: timeInterval) ?? "0 seconds"
    }

    private func formatEndTime() -> String {
      let endTime = Date().addingTimeInterval(timerManager.remainingTime)
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return formatter.string(from: endTime)
    }
  }

  // MARK: - Preset Artwork Loader

  private struct PresetArtworkLoader: View {
    let properties: MixerView.ArtworkProperties

    @State private var artworkImage: UIImage?
    @StateObject private var presetManager = PresetManager.shared

    var body: some View {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color.secondary.opacity(0.2))
        .frame(width: 32, height: 32)
        .overlay {
          if properties.soloSound != nil {
            Image(systemName: "headphones.circle.fill")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(properties.accentColor ?? .accentColor)
          } else if !properties.hasSelectedSounds && !properties.isQuickMix {
            Image(systemName: "speaker.slash.fill")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
          } else if let image = artworkImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            Image(systemName: "waveform")
              .font(.system(size: 12, weight: .medium))
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
#endif
