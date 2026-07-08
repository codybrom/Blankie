//
//  QuickMixWidget.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Quick Mix on the Home Screen the same way CarPlay's `QuickMixGridTemplate`
/// does it: a grid of individual sounds you tap in and out of the mix, not a
/// single "play Quick Mix" button — Dark Noise's "Multi Noise" widget uses
/// the same clean icon-grid shape for the same reason (a mix of interchangeable
/// generic sounds, not curated artwork worth showing).
struct QuickMixEntry: TimelineEntry {
  let date: Date
  let sounds: [WidgetQuickMixSound]
  /// Whether Quick Mix (not some other preset/solo sound) is the mode
  /// actually driving playback right now — the header's play/pause glyph
  /// only reads as "pause Quick Mix" when both this and `isPlaying` are true.
  let isActive: Bool
  let isPlaying: Bool
  /// The app's own accent (`GlobalSettings.customAccentColor`) — Quick Mix
  /// has no preset/sound of its own to theme with, so it uses this instead
  /// of the widget target's static `Color("AccentColor")` asset, which isn't
  /// necessarily the same color as the user's actual chosen accent.
  let accentColorName: String?
}

struct QuickMixProvider: TimelineProvider {
  func placeholder(in context: Context) -> QuickMixEntry {
    QuickMixEntry(date: .now, sounds: [], isActive: false, isPlaying: false, accentColorName: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (QuickMixEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QuickMixEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .never))
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
  let sound: WidgetQuickMixSound
  let size: CGFloat
  /// The user's real accent (resolved from the entry), so a selected tile
  /// matches the widget background instead of the target's static asset color.
  let accent: Color

  var body: some View {
    Button(intent: WidgetToggleQuickMixSoundIntent(fileName: sound.fileName)) {
      ZStack {
        Circle()
          .fill(sound.isSelected ? accent : Color.white.opacity(0.08))
        Image(systemName: sound.systemIconName)
          .font(.system(size: size * 0.35, weight: .medium))
          .foregroundStyle(.white)
      }
      .frame(width: size, height: size)
    }
    .buttonStyle(.plain)
  }
}

/// Brand badge + master play/pause, docked beside the grid rather than above
/// it — a column, not a header row, so it doesn't eat into the grid's own
/// vertical space. Lets Quick Mix's grid of otherwise-generic sound circles
/// still read as Blankie's and be played/paused as a whole without tapping
/// an individual sound circle.
private struct QuickMixSideControlView: View {
  let isActive: Bool
  let isPlaying: Bool

  var body: some View {
    VStack(spacing: 8) {
      BlankieBadge()
      Spacer(minLength: 0)
      Button(intent: ToggleBlankiePlaybackIntent()) {
        Image(systemName: isActive && isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: 26, height: 26)
          .background(.white, in: Circle())
      }
      .buttonStyle(.plain)
    }
  }
}

struct QuickMixWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  var entry: QuickMixProvider.Entry

  private let columnCount = 4
  private let gridSpacing: CGFloat = 12
  private let sideControlWidth: CGFloat = 26
  private let hstackSpacing: CGFloat = 10

  private var accent: Color { widgetAccentColor(entry.accentColorName) }

  // Largest tile we'd like per family — bigger on large to use its extra
  // vertical room, since with just 2 rows of sounds a `.systemLarge` canvas
  // would otherwise leave a dead zone below the grid.
  private var preferredTileSize: CGFloat { family == .systemLarge ? 108 : 60 }

  // …but clamped to what four columns actually fit in the available width. A
  // `.systemLarge` widget is no wider than a medium one on iPhone, so a fixed
  // 108 overflowed and clipped the right column; deriving from the real width
  // keeps the grid inside the canvas on every device.
  private func tileSize(fitting width: CGFloat) -> CGFloat {
    let available =
      width - sideControlWidth - hstackSpacing - CGFloat(columnCount - 1) * gridSpacing
    return max(0, min(preferredTileSize, available / CGFloat(columnCount)))
  }

  var body: some View {
    GeometryReader { geo in
      let tile = tileSize(fitting: geo.size.width)
      HStack(alignment: .center, spacing: hstackSpacing) {
        if entry.sounds.isEmpty {
          VStack(spacing: 4) {
            Image(systemName: "shuffle")
              .font(.title2)
              .foregroundStyle(.white.opacity(0.6))
            Text("Add sounds to Quick Mix in Blankie to see them here.")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.6))
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.fixed(tile), spacing: gridSpacing), count: columnCount),
            spacing: gridSpacing
          ) {
            ForEach(entry.sounds) { sound in
              QuickMixTileView(sound: sound, size: tile, accent: accent)
            }
          }
          .frame(maxWidth: .infinity)

          QuickMixSideControlView(isActive: entry.isActive, isPlaying: entry.isPlaying)
            .frame(width: sideControlWidth)
        }
      }
      // Fill the geometry so `QuickMixSideControlView`'s Spacer can span the
      // widget's full height instead of the HStack collapsing to its content.
      // (No manual padding — WidgetKit applies its own default content margins.)
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .containerBackground(for: .widget) {
      // Quick Mix has no preset of its own to theme with, so it uses the
      // app's own real accent rather than a per-session/per-preset color.
      widgetAccentGradient(widgetAccentColor(entry.accentColorName), colorScheme: colorScheme)
    }
  }
}

struct QuickMixWidget: Widget {
  let kind: String = "QuickMixWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickMixProvider()) { entry in
      QuickMixWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Quick Mix")
    .description("Tap sounds in and out of Blankie's Quick Mix.")
    .supportedFamilies([.systemMedium, .systemLarge])
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
