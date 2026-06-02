//
//  SoundIcon.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftData
import SwiftUI

struct SoundIcon: View {
  @ObservedObject var sound: Sound
  @ObservedObject var globalSettings = GlobalSettings.shared
  @ObservedObject var audioManager = AudioManager.shared
  #if os(macOS)
    // macOS honors the current preset's accent (see `accentColor`); observe the
    // manager so the grid re-tints when the active preset's color changes.
    @ObservedObject var presetManager = PresetManager.shared
  #endif
  @Environment(\.colorScheme) private var colorScheme
  let maxWidth: CGFloat

  @State private var showingEditSheet = false
  @State private var showingDeleteConfirmation = false

  private var configuration: Configuration {
    switch globalSettings.iconSize {
    case .small:
      let iconSize: CGFloat = 75  // Increased to match DraggableSoundIcon
      return Configuration(
        iconSize: iconSize,
        sliderWidth: 70,  // Keep slider width the same
        spacing: 1,
        padding: EdgeInsets(top: 2, leading: 1, bottom: 2, trailing: 1),
        fontSizeOffset: -7  // Smaller text for small icons
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
      // Prefer the active preset's accent, falling back to the global setting.
      presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
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

  // Get the script category for proper font styling
  var scriptCategory: Locale.ScriptCategory {
    Locale.current.scriptCategory
  }

  // Compute the appropriate font based on icon size and script category
  var titleFont: Font {
    let baseFont: Font

    // Start with callout and apply size adjustments
    switch globalSettings.iconSize {
    case .small:
      baseFont = .caption
    case .medium:
      baseFont = .callout
    case .large:
      baseFont = .body
    }

    // Apply weight based on script category
    let weightedFont = baseFont.weight(scriptCategory == .standard ? .regular : .thin)

    // Apply additional size increase for dense scripts
    if scriptCategory == .dense {
      return weightedFont.leading(.tight)
    }

    return weightedFont
  }

  /// Icon circle + name label as one group (the inner icon keeps its
  /// tap-to-toggle). In the macOS grid the reorder gesture is attached by the
  /// enclosing `SortableGridView` cell, not here.
  private var iconAndLabel: some View {
    VStack(spacing: configuration.spacing) {
      ZStack {
        Circle()
          .fill(backgroundFill)
          .frame(width: configuration.iconSize, height: configuration.iconSize)

        // Progress border (inner border)
        if globalSettings.showProgressBorder && sound.isSelected && audioManager.isGloballyPlaying {
          let borderSize = configuration.iconSize - configuration.borderWidth

          // Background track
          Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: configuration.borderWidth)
            .frame(width: borderSize, height: borderSize)

          // Progress indicator with TimelineView for 30 FPS updates
          TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            Circle()
              .trim(from: 0, to: max(0.01, getCurrentProgress()))  // Ensure minimum visibility
              .stroke(
                accentColor,
                style: StrokeStyle(lineWidth: configuration.borderWidth, lineCap: .round)
              )
              .frame(width: borderSize, height: borderSize)
              .rotationEffect(.degrees(-90))
          }
        }

        Image(systemName: sound.systemIconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: configuration.iconSize * 0.64, height: configuration.iconSize * 0.64)
          .foregroundColor(iconColor)
      }
      .frame(width: configuration.iconSize, height: configuration.iconSize)
      .contentShape(Circle())
      .accessibilityIdentifier("sound-\(sound.fileName)")
      .accessibilityAddTraits(.isButton)
      // Name the control for VoiceOver/Voice Control even when the visible title
      // is hidden by "Show Sound Names" (the identifier above is test-only).
      .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
      .onTapGesture {
        // If global playback is paused and this sound is already selected,
        // start global playback instead of deselecting the sound
        if !audioManager.isGloballyPlaying && sound.isSelected {
          audioManager.setGlobalPlaybackState(true)
        } else {
          sound.toggle()
        }
      }
      .sensoryFeedback(.selection, trigger: sound.isSelected)

      if globalSettings.showSoundNames {
        Text(LocalizedStringKey(sound.title))
          .font(titleFont)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(maxWidth: maxWidth - 20, minHeight: 32)  // Consistent padding and height for all sizes
          .foregroundColor(.primary)
          .contentShape(Rectangle())
      }
    }
  }

  var body: some View {
    VStack(spacing: configuration.spacing) {
      // Icon + label are the reorder drag region (large hit area, tap still
      // toggles); the slider below is intentionally outside it so a reorder
      // drag never hijacks the slider's gesture.
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
        // Built-in sound customization options
        Button("Customize Sound", systemImage: "slider.horizontal.3") {
          showingEditSheet = true
        }

        // Show reset option if sound has customizations
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
      debugLog("❌ SoundIcon: Failed to delete custom sound: \(error)")
    }
  }

  private func getCurrentProgress() -> Double {
    guard let player = sound.player, player.duration > 0 else {
      return 0.0
    }
    return player.currentTime / player.duration
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
      // Set up preview state using setter methods
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
