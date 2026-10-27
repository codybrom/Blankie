//
//  BlankieWidget.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
}

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry {
    NowPlayingEntry(date: .now, snapshot: .galleryPreview)
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(
      NowPlayingEntry(
        date: .now, snapshot: context.isPreview ? .galleryPreview : WidgetStateStore.current()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    let entry = NowPlayingEntry(date: .now, snapshot: WidgetStateStore.current())
    // The app reloads timelines on every change (`WidgetStateStore.publish`).
    completion(Timeline(entries: [entry], policy: .never))
  }
}

/// Gallery and placeholder content only. Installed widgets render the saved
/// snapshot, including empty states.
extension WidgetSnapshot {
  static var galleryPreview: WidgetSnapshot {
    let sounds: [(String, String)] = [
      ("rain", "cloud.rain"), ("storm", "cloud.bolt.rain"),
      ("wind", "wind"), ("waves", "water.waves"),
      ("stream", "humidity"), ("birds", "bird"),
      ("summer-night", "moon.stars.fill"), ("train", "tram.fill"),
    ]
    let favorites = sounds.map { name, icon in
      WidgetFavorite(
        token: "solo:\(name)",
        displayName: NSLocalizedString("sound.\(name)", comment: "Built-in sound name"),
        systemIconName: icon, thumbnailKey: nil, accentColorName: "blue", subtitle: nil)
    }
    return WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: false, title: favorites[0].displayName, subtitle: nil,
        soundSystemIconNames: [favorites[0].systemIconName], thumbnailKey: nil,
        activeToken: favorites[0].token, accentColorName: "blue"),
      favorites: favorites,
      quickMixSounds: sounds.enumerated().map { index, sound in
        WidgetQuickMixSound(
          fileName: sound.0, displayName: favorites[index].displayName,
          systemIconName: sound.1, isSelected: index < 3)
      },
      pinnableItems: favorites, defaultAccentColorName: "blue")
  }
}

/// Resolves `accentColorName`, falling back to the app's AccentColor asset.
func widgetAccentColor(_ name: String?) -> Color {
  name.flatMap { Color(fromString: $0) } ?? Color("AccentColor")
}

/// Accent card background. Stops are opaque `Color.mix` blends because WidgetKit
/// shows its own backdrop through translucent stops. Follows the Home Screen's
/// appearance, independent of the app's forced dark mode.
func widgetAccentGradient(_ accent: Color, colorScheme: ColorScheme) -> LinearGradient {
  if colorScheme == .dark {
    return LinearGradient(
      colors: [
        accent.mix(with: .black, by: 0.55),
        accent.mix(with: .black, by: 0.8),
        .black,
      ],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  return LinearGradient(
    colors: [
      accent.mix(with: Color("WidgetBackground"), by: 0.35),
      accent.mix(with: Color("WidgetBackground"), by: 0.7),
      Color("WidgetBackground"),
    ],
    startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Corner brand mark. `blankie.mark` bakes the B's counter into an even-odd path;
/// `blankie.symbol`'s layered counter fills in under flat widget rendering.
struct BlankieBadge: View {
  @Environment(\.widgetForeground) private var foreground
  var body: some View {
    Image("blankie.mark")
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
      .foregroundStyle(foreground)
      .widgetAccentable()
  }
}

/// Small card shared by `NowPlayingWidget` and `PinnedItemWidget`: framed
/// artwork, badge, title and a play/pause pill.
struct NowPlayingSmallCard<PlayIntent: AppIntent>: View {
  let title: String
  let subtitle: String?
  let thumbnailKey: String?
  let fallbackIcon: String?
  let accentColor: Color
  let isPlaying: Bool
  let playIntent: PlayIntent

  var body: some View {
    // At larger text sizes, shrink the artwork first, then drop the subtitle.
    ViewThatFits(in: .vertical) {
      cardContent(artworkSize: 56, spacing: 8, showsSubtitle: true)
      cardContent(artworkSize: 36, spacing: 6, showsSubtitle: true)
      cardContent(artworkSize: nil, spacing: 6, showsSubtitle: false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func cardContent(artworkSize: CGFloat?, spacing: CGFloat, showsSubtitle: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: spacing) {
      if let artworkSize {
        HStack(alignment: .top) {
          WidgetArtwork(
            thumbnailKey: thumbnailKey, fallbackIcon: fallbackIcon, accentColor: accentColor
          )
          .frame(width: artworkSize, height: artworkSize)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

          Spacer()
          BlankieBadge()
        }
      }

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.footnote.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if showsSubtitle, let subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
        }
      }

      Button(intent: playIntent) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 5) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            Text(isPlaying ? "Pause" : "Play")
              .lineLimit(1)
          }
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.32), in: Capsule())
        .overlay {
          Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct NowPlayingWidgetEntryView: View {
  @Environment(\.colorScheme) private var colorScheme
  var entry: NowPlayingProvider.Entry

  var body: some View {
    let playback = entry.snapshot.playback
    let accent = widgetAccentColor(playback.accentColorName)

    NowPlayingSmallCard(
      title: playback.title, subtitle: playback.subtitle, thumbnailKey: playback.thumbnailKey,
      fallbackIcon: playback.soundSystemIconNames.first, accentColor: accent,
      isPlaying: playback.isPlaying, playIntent: ToggleBlankiePlaybackIntent()
    )
    .containerBackground(for: .widget) {
      widgetAccentGradient(accent, colorScheme: colorScheme)
    }
  }
}

/// Cached thumbnail, or an accent circle with the sound's icon like the app's
/// `SoundIcon`. Border and glyph scale with size (30 to 74 pt).
struct WidgetArtwork: View {
  @Environment(\.displayScale) private var displayScale
  let thumbnailKey: String?
  let fallbackIcon: String?
  let accentColor: Color
  var borderColor: Color? = nil
  var showsFallbackIcon: Bool = true

  var body: some View {
    GeometryReader { geometry in
      let pixels = Int(ceil(max(geometry.size.width, geometry.size.height) * displayScale))
      if let thumbnailKey,
        let image = thumbnailImage(forKey: thumbnailKey, maxPixelSize: pixels)
      {
        image
          .resizable()
          .widgetAccentedRenderingMode(.fullColor)
          .aspectRatio(contentMode: .fill)
      } else {
        let side = min(geometry.size.width, geometry.size.height)
        ZStack {
          Circle()
            .fill(accentColor.opacity(0.2))
          Circle()
            .strokeBorder(borderColor ?? accentColor, lineWidth: max(1.5, side * 0.045))
          if showsFallbackIcon {
            Image(systemName: fallbackIcon ?? "waveform")
              .font(.system(size: side * 0.42, weight: .medium))
              .foregroundStyle(accentColor)
          }
        }
      }
    }
  }
}

struct NowPlayingWidget: Widget {
  let kind: String = "NowPlayingWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
      NowPlayingWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows what's playing in Blankie, with a play/pause button.")
    .supportedFamilies([.systemSmall])
  }
}

#Preview(as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry(
    date: .now,
    snapshot: WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: true, title: "Rainy Night", subtitle: "Rain, Thunder",
        soundSystemIconNames: ["cloud.rain.fill", "cloud.bolt.rain.fill"], thumbnailKey: nil,
        activeToken: nil, accentColorName: "blue"),
      favorites: [],
      quickMixSounds: [],
      pinnableItems: [],
      defaultAccentColorName: "blue"
    ))
}
