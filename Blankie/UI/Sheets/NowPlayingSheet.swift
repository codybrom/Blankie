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
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var backgroundImage: UIImage?
    @State private var currentPage: NowPlayingPage = .nowPlaying
    @State private var showingTimer = false
    @State private var presetToEdit: Preset?
    @State private var soundToEdit: Sound?
    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0
    @State private var controlTrigger = 0

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
                .blur(radius: 40)
                .opacity(0.4)
            } else {
              LinearGradient(
                colors: [
                  (audioManager.soloModeSound?.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor).opacity(0.6),
                  (audioManager.soloModeSound?.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor).opacity(0.3),
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
          .task(id: audioManager.soloModeSound?.id) {
            if audioManager.soloModeSound == nil, let preset = presetManager.currentPreset {
              backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
            } else if audioManager.soloModeSound != nil {
              backgroundImage = nil
            }
          }
          .sheet(isPresented: $showingTimer) {
            TimerSheetView()
              .presentationDetents([.medium, .large])
          }
          .sheet(item: $presetToEdit) { preset in
            EditPresetSheet(preset: preset, isPresented: $presetToEdit)
          }
          .sheet(item: $soundToEdit) { sound in
            SoundSheet(mode: .edit(sound))
          }
          .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: currentPage)
      }
    }

    // MARK: - Now Playing View

    @ViewBuilder
    private func nowPlayingView(in size: CGSize) -> some View {
      let artworkSize = size.width - 64

      VStack(spacing: 0) {
        Spacer()

        // Artwork
        Group {
          if let soloSound = audioManager.soloModeSound {
            Circle()
              .fill(Color.white.opacity(0.1))
              .frame(width: artworkSize, height: artworkSize)
              .overlay {
                Image(systemName: soloSound.systemIconName)
                  .font(.system(size: artworkSize * 0.35))
                  .foregroundColor(soloSound.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
              }
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
          } else if let image = backgroundImage {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: artworkSize, height: artworkSize)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
          } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.white.opacity(0.1))
              .frame(width: artworkSize, height: artworkSize)
              .overlay {
                BrandedBlankieIcon(
                  size: artworkSize * 0.35,
                  color: presetManager.currentPreset?.accentColor
                )
              }
          }
        }
        .padding(.horizontal, 32)

        Spacer()

        // Info section
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 4) {
            if let soloSound = audioManager.soloModeSound {
              Text(soloSound.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)

              Text("Solo Mode")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            } else {
              Button {
                showingPresetPicker = true
              } label: {
                HStack(spacing: 4) {
                  Text(presetManager.currentPreset?.activeTitle ?? "Blankie")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                  Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
                }
              }

              Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            }
          }

          Spacer()

          HStack(spacing: 12) {
            Button {
              controlTrigger += 1
              showingTimer = true
            } label: {
              Image(systemName: "timer")
                .font(.title2)
                .foregroundColor(timerManager.isTimerActive ? (audioManager.soloModeSound?.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor) : .white.opacity(0.7))
                .frame(width: 44, height: 44)
            }

            Button {
              controlTrigger += 1
              if let soloSound = audioManager.soloModeSound {
                soundToEdit = soloSound
              } else {
                presetToEdit = presetManager.currentPreset
              }
            } label: {
              Image(systemName: "slider.vertical.3")
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 44, height: 44)
            }
            .disabled(audioManager.soloModeSound == nil && presetManager.currentPreset == nil)
          }
        }
        .padding(.horizontal, 32)

        // Progress bar (solo mode only)
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
          .padding(.top, 24)
        }

        Spacer()
          .frame(maxHeight: 24)

        // Volume slider
        HStack(spacing: 15) {
          Image(systemName: "speaker.fill")
            .foregroundColor(.gray)
            .font(.caption)

          Slider(
            value: Binding(
              get: { globalSettings.volume },
              set: { globalSettings.setVolume($0) }
            ),
            in: 0 ... 1,
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

        Spacer()
      }
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

    private func formatTimerTime(_ timeInterval: TimeInterval) -> String {
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

    private var timerStatusText: String {
      if timerManager.remainingTime < 60 {
        return "Stops in \(formatTime(timerManager.remainingTime))"
      } else {
        return "Stops at \(formatEndTime())"
      }
    }

    private var subtitleText: String {
      let creatorName: String? = {
        if let name = presetManager.currentPreset?.creatorName, !name.isEmpty {
          return name
        }
        return nil
      }()

      if !audioManager.hasSelectedSounds {
        return "No sounds"
      }

      let statusPart: String
      if timerManager.isTimerActive {
        statusPart = timerStatusText
      } else {
        let soundCount = audioManager.sounds.filter { $0.isSelected }.count
        statusPart = "\(soundCount) sound\(soundCount == 1 ? "" : "s")"
      }

      if let creatorName {
        return "\(creatorName) • \(statusPart)"
      } else {
        return statusPart
      }
    }
  }

  #Preview {
    NowPlayingSheet(showingPresetPicker: .constant(false))
  }

#endif
