//
//  NowPlayingSheet.swift
//  Blankie
//
//  Apple Music-inspired Now Playing view with animated background
//

import AVFoundation
import AVKit
import MediaPlayer
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
    @State private var dragOffset: CGFloat = .zero
    var backgroundImage: PlatformImage?

    #if os(iOS)
      /// The app's own window — the foreground-active scene's key window, with
      /// sensible fallbacks. Sizing off this (not `UIScreen.bounds`) keeps the
      /// sheet correct under Split View / Slide Over / Stage Manager, where the
      /// window is smaller than the physical display.
      private var activeWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let scene =
          (scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)
          ?? (scenes.first as? UIWindowScene)
        return scene?.windows.first(where: { $0.isKeyWindow })
          ?? scene?.windows.first(where: { $0.safeAreaInsets.top > 0 })
          ?? scene?.windows.first
      }
    #endif

    private var screenSize: CGSize {
      #if os(iOS)
        if let window = activeWindow {
          return window.bounds.size
        }
      #endif
      return CGSize(width: 393, height: 852)
    }

    private var safeAreaInsets: EdgeInsets {
      #if os(iOS)
        if let window = activeWindow {
          let insets = window.safeAreaInsets
          return EdgeInsets(
            top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        }
      #endif
      return EdgeInsets()
    }
    @State private var currentPage: NowPlayingPage = .nowPlaying
    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0
    @State private var favoriteHapticTrigger = 0
    @State private var isFullyPresented = false

    private var artworkTaskID: String {
      let solo = audioManager.soloModeSound?.id.uuidString ?? ""
      let preset = presetManager.currentPreset?.id.uuidString ?? ""
      return "\(solo)-\(preset)"
    }

    var body: some View {
      ZStack {
        ZStack {
          // Background
          Color.black
            .overlay {
              if audioManager.soloModeSound == nil && !audioManager.isQuickMix,
                let image = backgroundImage
              {
                Image(uiImage: image)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
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

          // Content
          expandedPlayerView(screenSize)
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: currentPage)
        }
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: 38,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 38,
            style: .continuous
          )
        )
        .padding(.top, safeAreaInsets.top > 0 ? safeAreaInsets.top : 10)
      }
      .frame(width: screenSize.width, height: screenSize.height)
      .ignoresSafeArea()
      .offset(y: dragOffset)
      .gesture(dismissDrag)
      .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          isFullyPresented = true
        }
      }
    }

    /// Drag-to-dismiss for the whole sheet: drag down past the threshold to
    /// dismiss, otherwise spring back.
    private var dismissDrag: some Gesture {
      DragGesture()
        .onChanged { value in
          guard isFullyPresented else { return }
          if value.translation.height > 0 {
            dragOffset = value.translation.height
          }
        }
        .onEnded { value in
          guard isFullyPresented else { return }
          if value.translation.height > 150 || value.predictedEndTranslation.height > 200 {
            onDismiss?()
          } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              dragOffset = 0
            }
          }
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
          .frame(minHeight: 16, maxHeight: 32)

        artworkView(size: artworkSize)
          .padding(.horizontal, 32)

        Spacer()

        infoRow

        Spacer()
          .frame(maxHeight: 24)
        playbackProgressBar

        Spacer()
          .frame(maxHeight: 32)

        transportControls

        Spacer()
          .frame(maxHeight: 32)

        volumeSlider

        Spacer()
          .frame(maxHeight: 32)

        bottomActionsRow

        Spacer()
          .frame(height: max(12, safeAreaInsets.bottom))
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

          infoRow

          Spacer()
            .frame(maxHeight: 24)
          playbackProgressBar

          Spacer()
            .frame(maxHeight: 32)

          transportControls

          Spacer()
            .frame(maxHeight: 32)

          volumeSlider

          Spacer()
            .frame(maxHeight: 32)

          bottomActionsRow

          Spacer()
            .frame(height: max(12, safeAreaInsets.bottom))
        }
        .frame(width: size.width * 0.4)
        .padding(.trailing, 16)
      }
    }  // MARK: - Shared Components

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
      Group {
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
        } else if let image = backgroundImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
      .scaleEffect(audioManager.isGloballyPlaying ? 1.0 : 0.85)
      .shadow(
        color: .black.opacity(0.3),
        radius: audioManager.isGloballyPlaying ? 20 : 10,
        x: 0,
        y: audioManager.isGloballyPlaying ? 10 : 5
      )
      .animation(
        .spring(response: 0.4, dampingFraction: 0.6), value: audioManager.isGloballyPlaying
      )
    }

    private var currentProgressAnchor: (elapsed: TimeInterval, duration: TimeInterval)? {
      if timerManager.isTimerActive, timerManager.selectedDuration > 0 {
        let elapsed = timerManager.selectedDuration - timerManager.remainingTime
        return (max(0, elapsed), timerManager.selectedDuration)
      }

      let player =
        audioManager.soloModeSound?.player
        ?? audioManager.sounds
        .filter { $0.isSelected }
        .max { ($0.player?.duration ?? 0) < ($1.player?.duration ?? 0) }?
        .player

      guard let player, player.duration > 0 else { return nil }
      return (player.currentTime, player.duration)
    }

    @ViewBuilder
    private var playbackProgressBar: some View {
      let anchor = currentProgressAnchor
      let duration = anchor?.duration ?? 0

      if audioManager.isGloballyPlaying && duration > 0 {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
          playbackBar(duration: duration)
        }
      } else {
        playbackBar(duration: duration)
      }
    }

    @ViewBuilder
    private func playbackBar(duration: TimeInterval) -> some View {
      let anchor = currentProgressAnchor
      let elapsed = anchor?.elapsed ?? 0

      VStack(spacing: 8) {
        // Bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.white.opacity(0.3))
              .frame(height: 6)

            if duration > 0 {
              Capsule()
                .fill(Color.white)
                .frame(
                  width: max(0, min(geo.size.width, geo.size.width * CGFloat(elapsed / duration))),
                  height: 6)
            }
          }
        }
        .frame(height: 6)

        // Labels
        HStack {
          if timerManager.isTimerActive {
            Text("Pausing at \(timerEndTimeString)")
            Spacer()
            Text(formatTime(timerManager.remainingTime))
          } else {
            Text(duration > 0 ? formatTime(elapsed) : "--:--")
            Spacer()
            Text(duration > 0 ? formatTime(duration) : "--:--")
          }
        }
        .font(.caption2.monospacedDigit())
        .foregroundColor(.white.opacity(0.6))
      }
      .padding(.horizontal, 32)
    }

    private var timerEndTimeString: String {
      let endTime = Date().addingTimeInterval(timerManager.remainingTime)
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return formatter.string(from: endTime)
    }

    private var volumeSlider: some View {
      HStack(spacing: 15) {
        Image(systemName: "speaker.fill")
          .foregroundColor(.gray)
          .font(.caption)

        #if os(iOS)
          SystemVolumeSlider()
            .frame(height: 30)
        #else
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
        #endif

        Image(systemName: "speaker.wave.3.fill")
          .foregroundColor(.gray)
          .font(.caption)
      }
      .padding(.horizontal, 32)
    }

    // MARK: - Helper Properties

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

    // MARK: - Info Row

    @ViewBuilder
    private var infoRow: some View {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          if let soloSound = audioManager.soloModeSound {
            Text(soloSound.title)
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.white)
              .lineLimit(1)

            if let author = soloSound.creditedAuthor {
              Text(author)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }
          } else if let preset = presetManager.currentPreset {
            let displayName: String = {
              let name = preset.name
              if name == "Default" || name.starts(with: "Preset ") {
                // Static literal so it's extracted into the catalog and
                // localized here; real preset names render verbatim below.
                return String(localized: "Custom Mix")
              }
              return name
            }()
            Text(verbatim: displayName)
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.white)
              .lineLimit(1)

            if let creatorName = preset.creatorName, !creatorName.isEmpty {
              Text(creatorName)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }
          } else {
            Text(audioManager.isQuickMix ? "Quick Mix" : "Blankie")
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.white)
              .lineLimit(1)
          }
        }

        Spacer()

        HStack(spacing: 12) {
          if let token = favoriteToken {
            let starred = globalSettings.isStarred(token)
            Button {
              globalSettings.toggleStarred(token)
              favoriteHapticTrigger += 1
            } label: {
              Image(systemName: starred ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(starred ? accentColor : .white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
            }
            .accessibilityLabel(starred ? Text("Unfavorite") : Text("Favorite"))
          }

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
              Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
            }
            .accessibilityLabel(Text("Settings"))
          }
        }
      }
      .padding(.horizontal, 32)
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private var transportControls: some View {
      let canNavigate = audioManager.canNavigateNextPrevious
      HStack(spacing: 48) {
        Spacer()

        if canNavigate {
          Button {
            audioManager.navigateToPreviousPreset()
          } label: {
            Image(systemName: "backward.fill")
              .font(.system(size: 32))
              .foregroundColor(.white.opacity(0.8))
          }
          .accessibilityLabel(Text("Previous"))
        } else {
          Color.clear.frame(width: 32, height: 32)
        }

        Button {
          audioManager.togglePlayback()
        } label: {
          Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 48))
            .foregroundColor(.white)
            .frame(width: 60, height: 60, alignment: .center)
        }
        .accessibilityLabel(audioManager.isGloballyPlaying ? Text("Pause") : Text("Play"))

        if canNavigate {
          Button {
            audioManager.navigateToNextPreset()
          } label: {
            Image(systemName: "forward.fill")
              .font(.system(size: 32))
              .foregroundColor(.white.opacity(0.8))
          }
          .accessibilityLabel(Text("Next"))
        } else {
          Color.clear.frame(width: 32, height: 32)
        }

        Spacer()
      }
    }

    // MARK: - Bottom Actions Row

    @ViewBuilder
    private var bottomActionsRow: some View {
      HStack {
        // Left: Dismiss to Grid/List view
        Button {
          onDismiss?()
        } label: {
          Image(systemName: globalSettings.showingListView ? "list.bullet" : "square.grid.2x2")
            .foregroundColor(.white.opacity(0.7))
            .font(.system(size: 20, weight: .medium))
        }
        .accessibilityLabel(Text("Back to Mixer"))
        .frame(maxWidth: .infinity)

        // Middle: AirPlay / audio output route picker. The Playing Audio HIG
        // asks apps to permit rerouting of audio output when possible; this is
        // the system-standard control for it.
        #if os(iOS)
          AirPlayRoutePickerView()
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text("AirPlay"))
            .frame(maxWidth: .infinity)
        #else
          Spacer()
            .frame(maxWidth: .infinity)
        #endif

        // Right: Timer
        Button {
          showingTimer = true
        } label: {
          Image(systemName: "timer")
            .foregroundColor(timerManager.isTimerActive ? accentColor : .white.opacity(0.7))
            .font(.system(size: 20, weight: .medium))
        }
        .accessibilityLabel(Text("Timer"))
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 32)
    }

    // MARK: - Expanded Player View

    @ViewBuilder
    private func expandedPlayerView(_ size: CGSize) -> some View {
      VStack(spacing: 0) {
        dragIndicator
          .padding(.top, 12)
          .padding(.bottom, 16)

        nowPlayingView(in: size)
      }
    }

    private var dragIndicator: some View {
      Capsule()
        .fill(Color.white.opacity(0.3))
        .frame(width: 48, height: 5)
    }

    // MARK: - Helper Methods

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      let minutes = Int(timeInterval) / 60
      let seconds = Int(timeInterval) % 60
      return String(format: "%d:%02d", minutes, seconds)
    }

  }

  struct NowPlayingPreviewWrapper: View {
    init() {
      // Inject mock state so the preview isn't empty
      let mockPreset = Preset(
        id: UUID(),
        name: "Deep Sleep",
        soundStates: [],
        isDefault: false,
        createdVersion: nil,
        creatorName: "Blankie User"
      )
      PresetManager.shared.currentPreset = mockPreset
      AudioManager.shared.isGloballyPlaying = true
    }

    var body: some View {
      NowPlayingSheet(
        showingPresetPicker: .constant(false),
        showingTimer: .constant(false),
        presetToEdit: .constant(nil),
        soundToEdit: .constant(nil),
        showingQuickMixEditor: .constant(false)
      )
    }
  }

  #Preview("Portrait") {
    NowPlayingPreviewWrapper()
  }

  #Preview("Landscape", traits: .landscapeLeft) {
    NowPlayingPreviewWrapper()
  }

  // MARK: - System Volume Slider
  struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
      let volumeView = MPVolumeView(frame: .zero)
      // Hide the thumb for a clean bar look. This is a method on MPVolumeView
      // itself, so it works even before the internal UISlider subview exists
      // (the subview is created lazily after layout).
      volumeView.setVolumeThumbImage(UIImage(), for: .normal)
      return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
      // The UISlider subview is built lazily, so apply the track tints here —
      // updateUIView runs after the view is in the hierarchy and laid out,
      // whereas in makeUIView `subviews` is typically still empty.
      if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
        slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.7)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
      }
    }
  }

  // MARK: - AirPlay Route Picker

  #if os(iOS)
    /// System AirPlay / output-route button, tinted to match the white-on-glass
    /// Now Playing controls. Tapping it presents the system route picker.
    struct AirPlayRoutePickerView: UIViewRepresentable {
      func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = UIColor.white.withAlphaComponent(0.7)
        picker.activeTintColor = UIColor.white
        picker.prioritizesVideoDevices = false
        picker.overrideUserInterfaceStyle = .dark
        return picker
      }

      func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }
  #endif

#endif
