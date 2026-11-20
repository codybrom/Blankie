//
//  QuickMixWidget.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Quick Mix as a grid of sounds to tap in and out of the mix, like CarPlay's
/// `QuickMixGridTemplate`.
struct QuickMixEntry: TimelineEntry {
  let date: Date
  var color: WidgetColorChoice = .defaultAccent
  let sounds: [WidgetQuickMixSound]
  /// Whether Quick Mix is the active playback mode. Gates the play/pause control.
  let isActive: Bool
  let isPlaying: Bool
  /// The user's app accent (`GlobalSettings.customAccentColor`), which can differ
  /// from the widget target's static AccentColor asset.
  let accentColorName: String?
}

struct QuickMixProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> QuickMixEntry {
    galleryEntry
  }

  func snapshot(for configuration: WidgetAppearanceIntent, in context: Context) async
    -> QuickMixEntry
  {
    var result = context.isPreview ? galleryEntry : entry()
    result.color = configuration.color
    return result
  }

  func timeline(for configuration: WidgetAppearanceIntent, in context: Context) async
    -> Timeline<QuickMixEntry>
  {
    var result = entry()
    result.color = configuration.color
    return Timeline(entries: [result], policy: .never)
  }

  private var galleryEntry: QuickMixEntry {
    let snapshot = WidgetSnapshot.galleryPreview
    return QuickMixEntry(
      date: .now, sounds: snapshot.quickMixSounds, isActive: true, isPlaying: false,
      accentColorName: snapshot.defaultAccentColorName)
  }

  private func entry() -> QuickMixEntry {
    let snapshot = WidgetStateStore.current()
    return QuickMixEntry(
      date: .now, sounds: snapshot.quickMixSounds,
      isActive: snapshot.playback.activeToken == GlobalSettings.quickMixToken,
      isPlaying: snapshot.playback.isPlaying,
      accentColorName: snapshot.defaultAccentColorName)
  }
}

private struct QuickMixTileView: View {
  @Environment(\.widgetForeground) private var foreground
  @Environment(\.widgetRenderingMode) private var renderingMode
  let sound: WidgetQuickMixSound
  let size: CGFloat
  /// The user's accent from the entry, matching the widget background.
  let accent: Color

  var body: some View {
    Button(intent: WidgetToggleQuickMixSoundIntent(fileName: sound.fileName)) {
      ZStack {
        Circle()
          .fill(
            sound.isSelected
              ? (renderingMode == .accented ? Color.white.opacity(0.3) : accent)
              : foreground.opacity(0.10)
          )
          .widgetAccentable(sound.isSelected)
        Image(systemName: sound.systemIconName)
          .font(.system(size: size * 0.35, weight: .medium))
          .foregroundStyle(
            sound.isSelected
              ? (renderingMode == .accented ? .white : accent.contrastingLabel) : foreground)
      }
      .frame(width: size, height: size)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(sound.displayName)
    .accessibilityAddTraits(sound.isSelected ? .isSelected : [])
  }
}

/// Labeled sound buttons make the large widget useful without memorizing icons.
private struct QuickMixSoundRow: View {
  @Environment(\.widgetForeground) private var foreground
  @Environment(\.widgetRenderingMode) private var renderingMode
  let sound: WidgetQuickMixSound
  let accent: Color

  var body: some View {
    Button(intent: WidgetToggleQuickMixSoundIntent(fileName: sound.fileName)) {
      HStack(spacing: 8) {
        Image(systemName: sound.systemIconName)
          .font(.system(size: 21, weight: .medium))
          .frame(width: 28)
        Text(sound.displayName)
          .font(.caption.weight(.semibold))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(
        sound.isSelected
          ? (renderingMode == .accented ? .white : accent.contrastingLabel) : foreground
      )
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        sound.isSelected
          ? (renderingMode == .accented ? Color.white.opacity(0.3) : accent)
          : foreground.opacity(0.10),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .widgetAccentable(sound.isSelected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(sound.displayName)
    .accessibilityAddTraits(sound.isSelected ? .isSelected : [])
  }
}

/// XL gives each sound a full row with independent, relative volume controls.
private struct QuickMixVolumeRow: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  let sound: WidgetQuickMixSound
  let accent: Color
  let isActive: Bool

  private var foreground: Color {
    sound.isSelected ? (renderingMode == .accented ? .white : accent.contrastingLabel) : .white
  }

  var body: some View {
    HStack(spacing: 8) {
      Button(intent: WidgetToggleQuickMixSoundIntent(fileName: sound.fileName)) {
        HStack(spacing: 8) {
          Image(systemName: sound.systemIconName)
            .font(.system(size: 22, weight: .medium))
            .frame(width: 28)
          Text(sound.displayName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(sound.displayName)
      .accessibilityAddTraits(sound.isSelected ? .isSelected : [])

      volumeButton(delta: -5, icon: "minus")
      Text(Double(sound.volumePercent) / 100, format: .percent.precision(.fractionLength(0)))
        .font(.caption.monospacedDigit())
        .frame(width: 36)
        .accessibilityLabel(Text("Volume"))
      volumeButton(delta: 5, icon: "plus")
    }
    .foregroundStyle(foreground)
    .padding(.horizontal, 10)
    .background(
      sound.isSelected
        ? (renderingMode == .accented ? Color.white.opacity(0.3) : accent)
        : Color.white.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .widgetAccentable(sound.isSelected)
  }

  private func volumeButton(delta: Int, icon: String) -> some View {
    Button(intent: WidgetAdjustQuickMixVolumeIntent(fileName: sound.fileName, deltaPercent: delta))
    {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 32, height: 36)
        .background(foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .disabled(!isActive || (delta < 0 ? sound.volumePercent == 0 : sound.volumePercent == 100))
    .opacity(isActive ? 1 : 0.4)
    .accessibilityLabel(delta < 0 ? Text("Volume Down") : Text("Volume Up"))
    .accessibilityValue(sound.displayName)
  }
}

/// Only shown when Quick Mix is active and has a selected sound, so the
/// transport cannot unexpectedly pause another preset or start an empty mix.
private struct QuickMixTransportView: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  let isPlaying: Bool

  var body: some View {
    Button(
      intent: WidgetPlayFavoriteIntent(
        favoriteToken: GlobalSettings.quickMixToken, pauses: isPlaying)
    ) {
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(renderingMode == .accented ? .white : .black)
        .frame(width: 26, height: 26)
        .background(.white.opacity(renderingMode == .accented ? 0.2 : 1), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isPlaying ? "Pause" : "Play")
  }
}

private struct QuickMixSideControlView: View {
  let showsTransport: Bool
  let isPlaying: Bool

  var body: some View {
    VStack(spacing: 8) {
      BlankieBadge()
      Spacer(minLength: 0)
      if showsTransport {
        QuickMixTransportView(isPlaying: isPlaying)
      }
    }
  }
}

struct QuickMixWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: QuickMixProvider.Entry

  private let contentForeground: Color = .white

  private let columnCount = 4
  private let gridSpacing: CGFloat = 12
  private let sideControlWidth: CGFloat = 26
  private let hstackSpacing: CGFloat = 10

  private var accent: Color {
    entry.color.accent(defaultName: entry.accentColorName)
  }

  /// Fit the compact icon grid within both dimensions.
  private func tileSize(fitting size: CGSize) -> CGFloat {
    let rows = max(1, (min(entry.sounds.count, 8) + columnCount - 1) / columnCount)
    let width =
      size.width - sideControlWidth - hstackSpacing
      - CGFloat(columnCount - 1) * gridSpacing
    let height = size.height - CGFloat(rows - 1) * gridSpacing
    return max(
      0,
      min(
        60,
        width / CGFloat(columnCount), height / CGFloat(rows)))
  }

  private var showsTransport: Bool {
    entry.isActive && entry.sounds.contains(where: \.isSelected)
  }

  private var header: some View {
    HStack(spacing: 8) {
      BlankieBadge()
      Text("Quick Mix")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(contentForeground)
      Spacer(minLength: 0)
      if showsTransport {
        QuickMixTransportView(isPlaying: entry.isPlaying)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(minHeight: 26)
  }

  private var extraLargeBody: some View {
    let sounds = Array(entry.sounds.prefix(8))
    return VStack(spacing: 12) {
      header
      GeometryReader { geometry in
        let height = max(
          0, (geometry.size.height - CGFloat(sounds.count - 1) * 8) / CGFloat(sounds.count))
        VStack(spacing: 8) {
          ForEach(sounds) { sound in
            QuickMixVolumeRow(sound: sound, accent: accent, isActive: entry.isActive)
              .frame(height: height)
          }
        }
      }
    }
  }

  private var largeBody: some View {
    VStack(spacing: 10) {
      header

      let sounds = Array(entry.sounds.prefix(8))
      let rows = (sounds.count + 1) / 2
      GeometryReader { geometry in
        let height = max(0, (geometry.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows))
        VStack(spacing: 8) {
          ForEach(0..<rows, id: \.self) { row in
            HStack(spacing: 8) {
              ForEach(Array(sounds.dropFirst(row * 2).prefix(2))) { sound in
                QuickMixSoundRow(sound: sound, accent: accent)
              }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
          }
        }
      }
    }
  }

  var body: some View {
    Group {
      if family.isExtraLargePortrait && !entry.sounds.isEmpty {
        extraLargeBody
      } else if family == .systemLarge && !entry.sounds.isEmpty {
        largeBody
      } else {
        compactBody
      }
    }
    .environment(\.widgetForeground, .white)
    .containerBackground(for: .widget) {
      WidgetAppearanceBackground(choice: entry.color, defaultAccentName: entry.accentColorName)
    }
  }

  private var compactBody: some View {
    GeometryReader { geo in
      let tile = tileSize(fitting: geo.size)
      HStack(alignment: .center, spacing: hstackSpacing) {
        if entry.sounds.isEmpty {
          VStack(spacing: 4) {
            Image(systemName: "shuffle")
              .font(.title2)
              .foregroundStyle(contentForeground.opacity(0.6))
            Text("Add sounds to Quick Mix in Blankie to see them here.")
              .font(.caption)
              .foregroundStyle(contentForeground.opacity(0.6))
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.fixed(tile), spacing: gridSpacing), count: columnCount),
            spacing: gridSpacing
          ) {
            ForEach(Array(entry.sounds.prefix(8))) { sound in
              QuickMixTileView(sound: sound, size: tile, accent: accent)
            }
          }
          .frame(maxWidth: .infinity)

          QuickMixSideControlView(
            showsTransport: entry.isActive && entry.sounds.contains(where: \.isSelected),
            isPlaying: entry.isPlaying
          )
          .frame(width: sideControlWidth)
        }
      }
      // Full height so the side control's Spacer can span the widget.
      .frame(width: geo.size.width, height: geo.size.height)
    }

  }
}

struct QuickMixWidget: Widget {
  let kind: String = "QuickMixWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind, intent: WidgetAppearanceIntent.self, provider: QuickMixProvider()
    ) { entry in
      QuickMixWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Quick Mix")
    .description("Tap sounds in and out of Blankie's Quick Mix.")
    .supportedFamilies(interactiveWidgetFamilies)
  }
}

#Preview(as: .systemMedium) {
  QuickMixWidget()
} timeline: {
  QuickMixEntry(
    date: .now,
    sounds: [
      WidgetQuickMixSound(
        fileName: "rain", displayName: "Rain", systemIconName: "cloud.rain.fill", isSelected: true),
      WidgetQuickMixSound(
        fileName: "waves", displayName: "Waves", systemIconName: "water.waves", isSelected: false),
      WidgetQuickMixSound(
        fileName: "fireplace", displayName: "Fireplace", systemIconName: "flame.fill",
        isSelected: true),
      WidgetQuickMixSound(
        fileName: "white-noise", displayName: "White Noise", systemIconName: "waveform",
        isSelected: false),
    ],
    isActive: true, isPlaying: true, accentColorName: "purple")
}
