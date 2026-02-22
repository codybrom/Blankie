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
              // Preset with artwork: show blurred image
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 40)
                .opacity(0.4)
            } else {
              // Solo mode or preset without artwork: show gradient
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
            // Content
            expandedPlayerView(size, safeArea)
          }
          .task(id: audioManager.soloModeSound?.id) {
            // Load background image (only for presets, not solo mode)
            if audioManager.soloModeSound == nil, let preset = presetManager.currentPreset {
              backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
            } else if audioManager.soloModeSound != nil {
              // Clear background when in solo mode
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
    private var nowPlayingView: some View {
      VStack(spacing: 0) {
        Spacer()

        // Artwork
        VStack(spacing: 0) {
          if let soloSound = audioManager.soloModeSound {
            // Solo mode: show sound icon
            Circle()
              .fill(Color.white.opacity(0.1))
              .frame(width: 340, height: 340)
              .overlay {
                Image(systemName: soloSound.systemIconName)
                  .font(.system(size: 120))
                  .foregroundColor(soloSound.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
              }
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
          } else if let image = backgroundImage {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 340, height: 340)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
          } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.white.opacity(0.1))
              .frame(width: 340, height: 340)
              .overlay {
                BrandedBlankieIcon(
                  size: 120,
                  color: presetManager.currentPreset?.accentColor
                )
              }
          }
        }

        Spacer(minLength: 20)

        // Info section with menu
        VStack(spacing: 4) {
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
                Text(presetManager.currentPreset?.activeTitle ?? "Blankie")
                  .font(.title3)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
                  .lineLimit(1)

                Text(subtitleText)
                  .font(.subheadline)
                  .foregroundColor(.white.opacity(0.7))
              }
            }

            Spacer()

            // Edit button (preset or sound)
            Button {
              controlTrigger += 1
              if let soloSound = audioManager.soloModeSound {
                // Edit solo sound
                soundToEdit = soloSound
              } else {
                // Edit preset
                presetToEdit = presetManager.currentPreset
              }
            } label: {
              Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 44, height: 44)
            }
            .disabled(audioManager.soloModeSound == nil && presetManager.currentPreset == nil)
          }
          .padding(.horizontal, 32)
        }
        .padding(.bottom, 16)

        // Progress bar (solo mode only)
        if let soloSound = audioManager.soloModeSound, let duration = soloSound.duration {
          VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
              ZStack(alignment: .leading) {
                // Track
                Capsule()
                  .fill(.white.opacity(0.3))
                  .frame(height: 4)

                // Progress
                Capsule()
                  .fill(.white)
                  .frame(width: geometry.size.width * soloSound.playbackProgress, height: 4)
              }
            }
            .frame(height: 4)

            // Time labels
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
          .padding(.bottom, 24)
        }

        // Main controls (Timer, Play/Pause, Mixer)
        HStack(spacing: 60) {
          // Timer button
          Button {
            controlTrigger += 1
            showingTimer = true
          } label: {
            Image(systemName: timerManager.isTimerActive ? "timer" : "timer")
              .font(.system(size: 32))
              .foregroundColor(timerManager.isTimerActive ? (audioManager.soloModeSound?.customColor ?? presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor) : .white.opacity(0.7))
          }

          // Play/Pause button
          Button {
            if audioManager.hasSelectedSounds {
              playPauseTrigger += 1
              audioManager.togglePlayback()
            }
          } label: {
            Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 36))
              .foregroundColor(
                audioManager.hasSelectedSounds
                  ? .white
                  : .white.opacity(0.5)
              )
              .contentTransition(.symbolEffect(.replace))
              .offset(x: audioManager.isGloballyPlaying ? 0 : 2)
              .frame(width: 80, height: 80)
              .contentShape(Circle())
          }
          .glassEffect(.regular.interactive(), in: .circle)
          .disabled(!audioManager.hasSelectedSounds)
          .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playPauseTrigger)

          // Mixer button (hidden in solo mode or when no sounds)
          if audioManager.soloModeSound == nil && !audioManager.sounds.isEmpty {
            Button {
              controlTrigger += 1
              withAnimation(.spring(response: 0.3)) {
                currentPage = currentPage == .nowPlaying ? .mixer : .nowPlaying
              }
            } label: {
              Image(systemName: "slider.horizontal.3")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.7))
            }
          } else {
            // Spacer to maintain layout in solo mode or when no sounds
            Color.clear
              .frame(width: 32, height: 32)
          }
        }
        .padding(.bottom, 32)
        .sensoryFeedback(.selection, trigger: controlTrigger)

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
        .padding(.bottom, 40)
      }
    }

    // MARK: - Mixer View

    @ViewBuilder
    private var mixerView: some View {
      MixerView(onSwitchToNowPlaying: {
        withAnimation(.spring(response: 0.3)) {
          currentPage = .nowPlaying
        }
      })
    }

    // MARK: - Expanded Player View

    @ViewBuilder
    private func expandedPlayerView(_: CGSize, _: EdgeInsets) -> some View {
      VStack(spacing: 0) {
        if audioManager.soloModeSound != nil {
          // Solo mode: only show now playing (no swiping)
          nowPlayingView
        } else {
          // Preset mode: swipeable views
          TabView(selection: Binding(
            get: { currentPage.rawValue },
            set: { currentPage = NowPlayingPage(rawValue: $0) ?? .nowPlaying }
          )) {
            // Now Playing
            nowPlayingView
              .tag(NowPlayingPage.nowPlaying.rawValue)

            // Mixer
            mixerView
              .tag(NowPlayingPage.mixer.rawValue)
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
        }
      }
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
    NowPlayingSheet()
  }

#endif
