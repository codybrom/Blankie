//
//  SoundIcon.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftData
import SwiftUI
import os

struct SoundIcon: View {
  let sound: Sound
  let globalSettings = GlobalSettings.shared
  let audioManager = AudioManager.shared
  #if os(macOS)
    // macOS honors the current preset's accent (see `accentColor`). Observe the
    // manager so the grid re-tints when the active preset's color changes.
    let presetManager = PresetManager.shared
  #endif
  @Environment(\.colorScheme) private var colorScheme
  let maxWidth: CGFloat

  @State private var showingEditSheet = false
  @State private var showingDeleteConfirmation = false
  #if os(macOS)
    /// Drives the custom primary-colored focus ring (system ring disabled).
    @FocusState private var isTileFocused: Bool
    /// Limits the ring to keyboard focus. Clicks take focus on mouse-down,
    /// before the tap handler can clear it.
    @State private var focusCameFromKeyboard = false
  #endif

  private var configuration: Configuration {
    #if os(macOS)
      // macOS tiles scale with their cell (`maxWidth` from MacSoundGridView,
      // 120 to 200 pt). The `iconSize` setting has no macOS UI.
      return Configuration(
        iconSize: maxWidth * 0.85,
        sliderWidth: maxWidth * 0.7,
        spacing: 8,
        padding: EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10),
        fontSizeOffset: 0
      )
    #else
      switch globalSettings.iconSize {
      case .small:
        let iconSize: CGFloat = 75
        return Configuration(
          iconSize: iconSize,
          sliderWidth: 70,
          spacing: 1,
          padding: EdgeInsets(top: 2, leading: 1, bottom: 2, trailing: 1),
          fontSizeOffset: -7
        )
      case .medium:
        return Configuration(
          iconSize: 100,
          sliderWidth: 85,
          spacing: 8,
          padding: EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10),
          fontSizeOffset: 0
        )
      case .large:
        let iconSize = maxWidth * 0.85
        let sliderWidth = maxWidth * 0.75
        return Configuration(
          iconSize: iconSize,
          sliderWidth: sliderWidth,
          spacing: 8,
          padding: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20),
          fontSizeOffset: 6
        )
      }
    #endif
  }

  private struct Configuration {
    let iconSize: CGFloat
    let sliderWidth: CGFloat
    let spacing: CGFloat
    let padding: EdgeInsets
    let fontSizeOffset: CGFloat
    var borderWidth: CGFloat {
      switch GlobalSettings.shared.iconSize {
      case .small: return 4
      case .medium: return 4
      case .large: return 6
      }
    }
  }

  var accentColor: Color {
    #if os(macOS)
      // `themingPreset` is nil in single sound and Quick Mix, so those use the app accent.
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    #else
      globalSettings.customAccentColor ?? .accentColor
    #endif
  }

  var iconColor: Color {
    if !audioManager.isGloballyPlaying {
      return .gray
    }
    return sound.isSelected ? (accentColor) : .gray
  }

  var backgroundFill: Color {
    if !audioManager.isGloballyPlaying {
      return sound.isSelected ? Color.gray.opacity(0.2) : .clear
    }
    return sound.isSelected ? (accentColor).opacity(0.2) : .clear
  }

  var scriptCategory: Locale.ScriptCategory {
    Locale.current.scriptCategory
  }

  var titleFont: Font {
    let baseFont: Font

    switch globalSettings.iconSize {
    case .small:
      baseFont = .caption
    case .medium:
      baseFont = .callout
    case .large:
      baseFont = .body
    }

    let weightedFont = baseFont.weight(scriptCategory == .standard ? .regular : .thin)

    if scriptCategory == .dense {
      return weightedFont.leading(.tight)
    }

    return weightedFont
  }

  /// Icon circle and name label as one group (the icon keeps its tap to toggle).
  /// On macOS the enclosing `SortableGridView` cell attaches the reorder gesture.
  private var iconAndLabel: some View {
    VStack(spacing: configuration.spacing) {
      ZStack {
        Circle()
          .fill(backgroundFill)
          .frame(width: configuration.iconSize, height: configuration.iconSize)

        if globalSettings.showProgressBorder && sound.isSelected && audioManager.isGloballyPlaying {
          let borderSize = configuration.iconSize - configuration.borderWidth

          Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: configuration.borderWidth)
            .frame(width: borderSize, height: borderSize)

          TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            Circle()
              .trim(from: 0, to: max(0.01, getCurrentProgress()))
              .stroke(
                accentColor,
                style: StrokeStyle(lineWidth: configuration.borderWidth, lineCap: .round)
              )
              .frame(width: borderSize, height: borderSize)
              .rotationEffect(.degrees(-90))
          }
        }

        // A font glyph keeps SF Symbols' optical centering, while .resizable scales the
        // raw vector bounds and pushes some glyphs (washer.fill) off-center.
        Image(systemName: sound.systemIconName)
          .font(.system(size: configuration.iconSize * 0.58))
          .foregroundColor(iconColor)
      }
      .frame(width: configuration.iconSize, height: configuration.iconSize)
      .contentShape(Circle())
      // Represent as one button element so the icon name isn't announced
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier("sound-\(sound.fileName)")
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(sound.isSelected ? [.isSelected] : [])
      // Name the control for VoiceOver/Voice Control even when the visible title
      // is hidden by "Show Sound Names" (the identifier above is test-only).
      .accessibilityLabel(Text(sound.localizedTitle))
      .onTapGesture {
        #if os(macOS)
          // Clicks must not keep keyboard focus. The ring is for Tab navigation.
          isTileFocused = false
        #endif
        activateTile()
      }
      .sensoryFeedback(.selection, trigger: sound.isSelected)
      #if os(macOS)
        // Volume is a separate VoiceOver stop so the rotor stays reliable
        .accessibilityAction { DispatchQueue.main.async { activateTile() } }
        // Plain .focusable() stays tabbable with the system Keyboard navigation
        // setting off (.activate gates on it). The tap handler undoes click focus.
        .focusable()
        .focused($isTileFocused)
        // The overlay below draws a primary-colored ring.
        .focusEffectDisabled()
        .onChange(of: isTileFocused) { _, focused in
          guard focused else { return }
          // Tab arrives as a keyDown. Clicks are mouse events and launch focus
          // has no event, so only a keyDown shows the ring.
          focusCameFromKeyboard = NSApp.currentEvent?.type == .keyDown
        }
        .overlay {
          if isTileFocused && focusCameFromKeyboard {
            Circle()
            .strokeBorder(Color.primary, lineWidth: 2)
            .padding(-4)
          }
        }
        .onKeyPress(.return) {
          DispatchQueue.main.async { activateTile() }
          return .handled
        }
        .onKeyPress(.space) {
          DispatchQueue.main.async { activateTile() }
          return .handled
        }
        .onKeyPress(.upArrow) {
          DispatchQueue.main.async { adjustVolume(.increment) }
          return .handled
        }
        .onKeyPress(.downArrow) {
          DispatchQueue.main.async { adjustVolume(.decrement) }
          return .handled
        }
        .onKeyPress(.escape) {
          // Clear keyboard focus (matches clicking empty grid space). The
          // next Tab restarts from the first tile.
          DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
          return .handled
        }
      #endif

      if globalSettings.showSoundNames {
        HStack(spacing: 4) {
          Text(sound.localizedTitle)
            .font(titleFont)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundColor(.primary)

          if sound.isMusic {
            MusicTagBadge(
              isActive: sound.isSelected && audioManager.isGloballyPlaying,
              accentColor: accentColor)
          }
        }
        .frame(maxWidth: maxWidth - 20, minHeight: 32)
        .contentShape(Rectangle())
        // Hide so VoiceOver only reads once
        .accessibilityHidden(true)
      }
    }
  }

  /// The tile's action for tap, Return/Space and VoiceOver. Toggles the sound,
  /// or while playback is paused selects it and starts playing.
  private func activateTile() {
    audioManager.toggleOrResume(sound)
  }

  #if os(macOS)
    /// Volume nudge for the tile's VoiceOver adjustable action and the Up/Down arrow keys. No-op when the sound is off (its slider is disabled then).
    private func adjustVolume(_ direction: AccessibilityAdjustmentDirection) {
      guard sound.isSelected else { return }
      // 1/16, matching the master-volume shortcut and macOS volume keys
      let step: Float = 1.0 / 16.0
      switch direction {
      case .increment: sound.volume = min(1, sound.volume + step)
      case .decrement: sound.volume = max(0, sound.volume - step)
      @unknown default: break
      }
    }
  #endif

  var body: some View {
    VStack(spacing: configuration.spacing) {
      // Icon and label are the reorder drag region. The slider stays outside it
      // so a reorder drag never takes the slider's gesture.
      iconAndLabel
        .reorderHandle()

      Slider(
        value: Binding(
          get: { Double(sound.volume) },
          set: { sound.volume = Float($0) }
        ), in: 0...1
      )
      .frame(width: configuration.sliderWidth)
      .tint(
        audioManager.isGloballyPlaying
          ? (sound.isSelected ? (accentColor) : .gray) : .gray
      )
      .disabled(!sound.isSelected)
      .accessibilityLabel(Text(sound.localizedTitle))
      .accessibilityValue(
        Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0))))
      )
    }
    .padding(.vertical, configuration.padding.top)
    .padding(.horizontal, configuration.padding.leading)
    .frame(width: maxWidth)
    .contextMenu {
      if sound.isCustom {
        Button("Edit Sound", systemImage: "pencil") {
          showingEditSheet = true
        }

        Button("Delete Sound", systemImage: "trash", role: .destructive) {
          showingDeleteConfirmation = true
        }
      } else {
        Button("Customize Sound", systemImage: "slider.horizontal.3") {
          showingEditSheet = true
        }

        if SoundCustomizationManager.shared.getCustomization(for: sound.fileName)?.hasCustomizations
          == true
        {
          Button("Reset to Default", systemImage: "arrow.counterclockwise") {
            SoundCustomizationManager.shared.resetCustomizations(for: sound.fileName)
          }
        }
      }
    }
    .sheet(isPresented: $showingEditSheet) {
      SoundSheet(mode: .edit(sound))
    }
    .alert(
      Text("Delete Sound"),
      isPresented: $showingDeleteConfirmation
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if sound.isCustom, let customSoundDataID = sound.customSoundDataID,
          let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
        {
          deleteCustomSound(customSoundData)
        }
      }
    } message: {
      Text(
        "Are you sure you want to delete '\(sound.title)'? This action cannot be undone."
      )
    }
  }

  private func deleteCustomSound(_ customSoundData: CustomSoundData) {
    let result = CustomSoundManager.shared.deleteCustomSound(customSoundData)

    if case .failure(let error) = result {
      Logger.ui.error("SoundIcon: Failed to delete custom sound: \(error, privacy: .public)")
    }
  }

  private func getCurrentProgress() -> Double {
    guard sound.playbackDuration > 0 else {
      return 0.0
    }
    return sound.playbackPosition / sound.playbackDuration
  }
}

#if DEBUG
  #Preview("Selected") {
    SoundIcon(
      sound: Sound(
        title: "Rain",
        systemIconName: "cloud.rain",
        fileName: "rain"
      ),
      maxWidth: 150
    )
    .onAppear {
      GlobalSettings.shared.setAccentColor(.blue)
      GlobalSettings.shared.setVolume(0.7)
    }
  }

  #Preview("Not Selected") {
    SoundIcon(
      sound: Sound(
        title: "Storm",
        systemIconName: "cloud.bolt.rain",
        fileName: "storm"
      ),
      maxWidth: 150
    )
  }

  #Preview("Long Title") {
    SoundIcon(
      sound: Sound(
        title: "Very Long Sound Name That Should Truncate",
        systemIconName: "speaker.wave.3.fill",
        fileName: "test"
      ),
      maxWidth: 150
    )
  }

  #Preview("Grid Layout") {
    LazyVGrid(
      columns: [
        GridItem(.fixed(150)),
        GridItem(.fixed(150)),
      ], spacing: 20
    ) {
      SoundIcon(
        sound: Sound(
          title: "Rain",
          systemIconName: "cloud.rain",
          fileName: "rain"
        ),
        maxWidth: 150
      )
      SoundIcon(
        sound: Sound(
          title: "Storm",
          systemIconName: "cloud.bolt.rain",
          fileName: "storm"
        ),
        maxWidth: 150
      )
      SoundIcon(
        sound: Sound(
          title: "Wind",
          systemIconName: "wind",
          fileName: "wind"
        ),
        maxWidth: 150
      )
      SoundIcon(
        sound: Sound(
          title: "Waves",
          systemIconName: "water.waves",
          fileName: "waves"
        ),
        maxWidth: 150
      )
    }
    .padding()
  }
#endif
