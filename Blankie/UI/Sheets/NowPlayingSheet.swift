//
//  NowPlayingSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 11/24/25.
//
//  Apple Music-inspired Now Playing view with animated background
//

import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI

#if os(iOS) || os(visionOS)

  struct NowPlayingSheet: View {
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var audioManager = AudioManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var timerManager = TimerManager.shared

    @State private var globalSettings = GlobalSettings.shared
    /// Presented from inside the cover — a sheet attached to the base
    /// hierarchy can't present over a fullScreenCover.
    @State private var showingTimer = false
    var backgroundImage: PlatformImage?

    /// CarPlay routes audio (and volume) to the car, so the in-app volume bar
    /// has nothing to control there — hide the whole row when connected.
    /// Reads AudioManager's published flag (fed by CarPlayAudioBridge).
    private var isCarPlayConnected: Bool {
      audioManager.isCarPlayConnected
    }

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
    @State private var isEditingVolume = false
    @State private var playPauseTrigger = 0
    @State private var favoriteHapticTrigger = 0

    private var artworkTaskID: String {
      let solo = audioManager.soloModeSound?.id.uuidString ?? ""
      let preset = presetManager.currentPreset?.id.uuidString ?? ""
      return "\(solo)-\(preset)"
    }

    var body: some View {
      // Size to the presenting sheet (not the window): a large-detent sheet is a
      // touch shorter than the full window, so framing to the sheet keeps the
      // bottom controls on screen instead of clipped.
      GeometryReader { proxy in
        ZStack {
          // Background fills the whole sheet. Rounded top corners show while the
          // zoom transition is mid-flight and behind the sheet's own rounding.
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
            .clipShape(
              UnevenRoundedRectangle(
                topLeadingRadius: 38,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 38,
                style: .continuous
              )
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

          // Content stays within the top safe area so the drag handle and
          // everything below it sit clear of the Dynamic Island.
          expandedPlayerView(proxy.size)
            .padding(.top, proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : 10)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .ignoresSafeArea()
      .sheet(isPresented: $showingTimer) {
        // Detents and presentationSizing don't compose — when both are set the
        // detents win and presentationSizing is ignored, leaving iPad stuck at
        // the short `.medium` height that clips the picker. So size by idiom:
        // iPad gets a standard `.form` sheet (tall enough, no detents); iPhone
        // keeps its draggable medium/large detents.
        if isPad {
          TimerSheetView()
            .presentationSizing(.form)
        } else {
          TimerSheetView()
            .presentationDetents([.medium, .large])
        }
      }
    }

    // MARK: - Now Playing View

    private var isPad: Bool {
      #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
      #else
        return false
      #endif
    }

    @ViewBuilder
    private func nowPlayingView(in size: CGSize) -> some View {
      let aspect = size.height > 0 ? size.width / size.height : 1
      if isPad {
        // iPad: every size class is wide enough that the phone's full-width
        // stacked layout sprawls, and tall enough that its single flexible
        // spacer leaves a dead gap under the artwork. Use a centered, balanced
        // column tuned for the larger canvas.
        padNowPlaying(in: size)
      } else if aspect > 1.6 {
        // Side-by-side landscape only when the area is meaningfully wider than
        // tall (iPhone landscape) — otherwise the HStack gets cramped.
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

        if !isCarPlayConnected {
          volumeSlider

          Spacer()
            .frame(maxHeight: 32)
        }

        bottomActionsRow

        Spacer()
          .frame(height: max(12, safeAreaInsets.bottom))
      }
    }

    // MARK: - iPad Layout

    @ViewBuilder
    private func padNowPlaying(in size: CGSize) -> some View {
      // Width-capped column so controls and artwork stay readable rather than
      // stretching across the whole window.
      let columnWidth = min(size.width - 96, 600)
      // Cap the artwork by height too so it doesn't dominate in landscape, where
      // the canvas is short.
      let artworkSize = max(min(columnWidth, size.height * 0.45), 160)

      VStack(spacing: 0) {
        // Flexible top and a flexible gap before the bottom row balance the
        // free vertical space, so the artwork + controls cluster sits centered
        // instead of pinned to the top with a gap beneath it.
        Spacer(minLength: 24)

        artworkView(size: artworkSize)

        Spacer().frame(height: 40)

        infoRow

        Spacer().frame(height: 24)
        playbackProgressBar

        Spacer().frame(height: 32)

        transportControls

        Spacer().frame(height: 32)

        if !isCarPlayConnected {
          volumeSlider
        }

        Spacer(minLength: 24)

        bottomActionsRow

        Spacer()
          .frame(height: max(12, safeAreaInsets.bottom))
      }
      .frame(width: columnWidth)
      .frame(maxWidth: .infinity)
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

          if !isCarPlayConnected {
            volumeSlider

            Spacer()
              .frame(maxHeight: 32)
          }

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
          // Solo has no preset artwork: the shared fallback with the sound's
          // own icon and the app accent.
          FallbackArtwork(
            glyph: .symbol(soloSound.systemIconName),
            accent: globalSettings.customAccentColor ?? .accentColor,
            size: size,
            glyphFraction: 0.4
          )
        } else if let image = backgroundImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
          // No custom/animated artwork: Quick Mix → grid, All Blankie Sounds →
          // the Blankie mark, a custom preset → a montage of its playing sounds.
          FallbackArtwork(
            glyph: .playback(
              isQuickMix: audioManager.isQuickMix,
              isDefaultPreset: presetManager.currentPreset?.isDefault ?? true,
              icons: audioManager.playingSoundIcons()),
            accent: presetManager.currentPreset?.accentColor
              ?? globalSettings.customAccentColor ?? .accentColor,
            size: size,
            glyphFraction: 0.5
          )
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
      .accessibilityHidden(true)
    }

    private var currentProgressAnchor: (elapsed: TimeInterval, duration: TimeInterval)? {
      if timerManager.isTimerActive, timerManager.selectedDuration > 0 {
        let elapsed = timerManager.selectedDuration - timerManager.remainingTime
        return (max(0, elapsed), timerManager.selectedDuration)
      }

      let anchorSound =
        audioManager.soloModeSound
        ?? audioManager.sounds
        .filter { $0.isSelected }
        .max { $0.playbackDuration < $1.playbackDuration }

      guard let anchorSound, anchorSound.playbackDuration > 0 else { return nil }
      return (anchorSound.playbackPosition, anchorSound.playbackDuration)
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
        .accessibilityHidden(true)

        // Labels
        HStack {
          if timerManager.isTimerActive {
            Text("Pausing at \(timerEndTimeString)")
            Spacer()
            Text(formatTime(-timerManager.remainingTime))
          } else {
            Text(duration > 0 ? formatTime(elapsed) : "--:--")
            Spacer()
            if duration > 0 {
              HStack(spacing: 3) {
                Text(formatTime(duration))
                Image(systemName: "repeat")
                  .accessibilityHidden(true)
              }
            } else {
              Text("--:--")
            }
          }
        }
        .font(.caption2.monospacedDigit())
        .foregroundColor(.white.opacity(0.6))
      }
      .padding(.horizontal, 32)
    }

    private var timerEndTimeString: String {
      (timerManager.getEndTime() ?? Date())
        .formatted(date: .omitted, time: .shortened)
    }

    // Volume controls. While mixing with other audio the iOS hardware slider
    // would move every app's level together, so it can't isolate Blankie. In
    // that mode we swap in a slider bound to volumeWithOtherAudio — Blankie's
    // level over the other media — and label it so the change is obvious.
    @ViewBuilder
    private var volumeSlider: some View {
      #if os(iOS) || os(visionOS)
        if globalSettings.mixWithOthers {
          blankieVolumeRow
        } else {
          systemVolumeRow
        }
      #else
        systemVolumeRow
      #endif
    }

    private var systemVolumeRow: some View {
      HStack(spacing: 15) {
        Image(systemName: "speaker.fill")
          .foregroundColor(.gray)
          .font(.caption)
          .accessibilityHidden(true)

        #if os(iOS)
          SystemVolumeSlider()
            .frame(height: 30)
            .accessibilityLabel(Text("Volume"))
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
          .accessibilityLabel(Text("Volume"))
          .accessibilityValue(
            Text(Double(globalSettings.volume).formatted(.percent.precision(.fractionLength(0)))))
        #endif

        Image(systemName: "speaker.wave.3.fill")
          .foregroundColor(.gray)
          .font(.caption)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 32)
    }

    #if os(iOS) || os(visionOS)
      /// Mixing mode: the slider controls Blankie's own level over the other
      /// audio (volumeWithOtherAudio), tinted with the accent and headed
      /// "Blankie Volume" so it's clearly not the device volume.
      private var blankieVolumeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
          Text("Blankie Volume with Media")
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.7))
            .accessibilityHidden(true)

          HStack(spacing: 15) {
            Image(systemName: "speaker.fill")
              .foregroundColor(.gray)
              .font(.caption)
              .accessibilityHidden(true)

            Slider(
              value: Binding(
                get: { globalSettings.volumeWithOtherAudio },
                set: { globalSettings.setVolumeWithOtherAudio($0) }
              ),
              in: 0...1
            )
            .tint(accentColor)
            .accessibilityLabel(Text("Blankie Volume with Media"))
            .accessibilityValue(
              Text(
                globalSettings.volumeWithOtherAudio.formatted(
                  .percent.precision(.fractionLength(0)))))

            Image(systemName: "speaker.wave.3.fill")
              .foregroundColor(.gray)
              .font(.caption)
              .accessibilityHidden(true)
          }
        }
        .padding(.horizontal, 32)
      }
    #endif

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

            if soloSound.isCustom, let author = soloSound.creditedAuthor {
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
        .accessibilityElement(children: .combine)

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
            #if os(iOS)
              .frame(minWidth: 44, minHeight: 44)
            #endif
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
          #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
          #endif
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
          #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
          #endif
        } else {
          Color.clear.frame(width: 32, height: 32)
        }

        Spacer()
      }
    }

    // MARK: - Bottom Actions Row

    private var bottomActionsRow: some View {
      GlassEffectContainer(spacing: 20) {
        bottomActionsContent
      }
    }

    private var bottomActionsContent: some View {
      HStack(spacing: 20) {
        // Left: collapse back to the mini bar
        Button {
          onDismiss?()
        } label: {
          Image(systemName: "chevron.down")
            .foregroundColor(.white.opacity(0.7))
            .font(.system(size: 20, weight: .medium))
            .frame(width: 56, height: 56)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
        .modifier(NowPlayingActionGlass())

        // Middle: AirPlay / audio output route picker. The Playing Audio HIG
        // asks apps to permit rerouting of audio output when possible; this is
        // the system-standard control for it.
        #if os(iOS)
          AirPlayRouteButton(
            activeColor: accentColor,
            inactiveColor: .white.opacity(0.35)
          )
          .frame(width: 44, height: 44)
          .accessibilityLabel(Text("AirPlay"))
          .frame(width: 56, height: 56)
          .contentShape(Circle())
          .modifier(NowPlayingActionGlass())
        #endif

        // Right: Timer
        Button {
          showingTimer = true
        } label: {
          Image(systemName: "timer")
            .foregroundColor(timerManager.isTimerActive ? accentColor : .white.opacity(0.7))
            .font(.system(size: 20, weight: .medium))
            .frame(width: 56, height: 56)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Timer"))
        .modifier(NowPlayingActionGlass())
      }
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
        .accessibilityHidden(true)
    }

    // MARK: - Helper Methods

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      timeInterval.minuteSecondClock
    }

  }

  /// Liquid Glass circle for the bottom action buttons
  private struct NowPlayingActionGlass: ViewModifier {
    func body(content: Content) -> some View {
      content.glassEffect(.regular.interactive(), in: .circle)
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
      NowPlayingSheet()
    }
  }

  #Preview("Portrait") {
    NowPlayingPreviewWrapper()
  }

  #Preview("Landscape", traits: .landscapeLeft) {
    NowPlayingPreviewWrapper()
  }

  // MARK: - System Volume Slider

  final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
      let rect = super.volumeSliderRect(forBounds: bounds)
      return CGRect(
        x: rect.minX, y: bounds.midY - rect.height / 2,
        width: rect.width, height: rect.height)
    }
  }

  struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
      let volumeView = CenteredVolumeView(frame: .zero)
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
    /// System AirPlay / output-route button. Defaults match the white-on-glass
    /// Now Playing controls; the mini bar passes adaptive label colors instead.
    struct AirPlayRoutePickerView: UIViewRepresentable {
      var tint: UIColor = UIColor.white.withAlphaComponent(0.7)
      var activeTint: UIColor = .white
      var forcesDarkAppearance = true

      func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = tint
        picker.activeTintColor = activeTint
        picker.prioritizesVideoDevices = false
        if forcesDarkAppearance {
          picker.overrideUserInterfaceStyle = .dark
        }
        return picker
      }

      // The system route / "Share Audio" sheet this button presents is rendered
      // outside the app's window — it never enters the window's presentation
      // chain, and dark window/VC overrides don't reach it (verified on device).
      // Per Apple's "Choosing a specific interface style for your iOS app", only a
      // process-level Info.plist UIUserInterfaceStyle = Dark forces system sheets
      // dark (i.e. making the whole app dark-only), so there is intentionally no
      // per-sheet appearance override here.
      func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }

    /// Watches the live output route and maps it to an SF Symbol plus whether
    /// audio is leaving the built-in speaker. Drives the AirPlay button's icon
    /// and tint so it reflects the kind of device audio is going to.
    ///
    /// Deliberately maps only to *generic* symbols (headphones, hifispeaker, car,
    /// tv, airplayaudio) keyed off `portType`, the one reliable signal. We do NOT
    /// try to show the specific product (AirPods, Beats, HomePod, Apple TV): those
    /// glyphs are license-restricted to their exact product ("may only be used to
    /// refer to Apple's AirPods"), and the only model hint the route exposes is
    /// `portName` — a free, user-renameable string. Guessing the product from it
    /// could incorrectly paint a restricted Apple/Beats glyph on the wrong (or a
    /// third-party) device, which violates the SF Symbols license. So we don't.
    ///
    /// iOS 27 (in beta, unreleased) adds `AVSystemRoute.routeSymbolName`, where
    /// the system hands back an already-vetted symbol — safe to show verbatim.
    /// But it only covers routes from a media device extension (third-party
    /// AirPlay-style receivers), not AirPods/HomePod/wired/built-in, so this
    /// generic mapping still carries the everyday cases.
    final class AudioRouteObserver: ObservableObject {
      @Published private(set) var symbolName = "airplayaudio"
      @Published private(set) var isExternal = false

      init() {
        update()
        NotificationCenter.default.addObserver(
          self, selector: #selector(routeChanged),
          name: AVAudioSession.routeChangeNotification, object: nil)
      }

      @objc private func routeChanged() {
        DispatchQueue.main.async { [weak self] in self?.update() }
      }

      private func update() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else {
          (symbolName, isExternal) = ("airplayaudio", false)
          return
        }
        switch port.portType {
        case .builtInSpeaker, .builtInReceiver:
          (symbolName, isExternal) = ("airplayaudio", false)
        case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
          // Generic personal-audio glyph for any wired/Bluetooth headset; we
          // can't (and per the license shouldn't) claim it's a specific model.
          (symbolName, isExternal) = ("headphones", true)
        case .carAudio:
          (symbolName, isExternal) = ("car", true)
        case .HDMI, .displayPort:
          (symbolName, isExternal) = ("tv", true)
        case .usbAudio, .lineOut, .thunderbolt:
          (symbolName, isExternal) = ("hifispeaker.fill", true)
        case .airPlay:
          // HomePod/Apple TV/AirPlay speakers all land here; the generic AirPlay
          // glyph is both license-safe and the honest icon (class is unknowable).
          (symbolName, isExternal) = ("airplayaudio", true)
        default:
          (symbolName, isExternal) = ("airplayaudio", true)
        }
      }
    }

    /// AirPlay control that shows a themed, route-category icon while still
    /// presenting the system route picker. The icon is tinted with the theme
    /// accent when audio is routed off-device and dimmed when it isn't; a
    /// transparent `AVRoutePickerView` sits on top to capture the tap.
    struct AirPlayRouteButton: View {
      var activeColor: Color
      var inactiveColor: Color
      @StateObject private var route = AudioRouteObserver()

      var body: some View {
        AirPlayRoutePickerView(tint: .clear, activeTint: .clear)
          .overlay {
            Image(systemName: route.symbolName)
              .font(.system(size: 20, weight: .medium))
              .foregroundStyle(route.isExternal ? activeColor : inactiveColor)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
      }
    }
  #endif

#endif
