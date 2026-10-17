//
//  FavoritesWidget.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FavoritesEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
}

struct FavoritesProvider: TimelineProvider {
  func placeholder(in context: Context) -> FavoritesEntry {
    FavoritesEntry(date: .now, snapshot: .galleryPreview)
  }

  func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
    completion(
      FavoritesEntry(
        date: .now, snapshot: context.isPreview ? .galleryPreview : WidgetStateStore.current()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
    let entry = FavoritesEntry(date: .now, snapshot: WidgetStateStore.current())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

/// Ring + play/pause glyph shown on whichever tile matches the currently
/// active token, so tapping it is obviously "pause this" rather than
/// "restart this" — the same tile, no separate now-playing row needed.
private struct ActiveIndicator: View {
  let isPlaying: Bool

  var body: some View {
    ZStack {
      Color.black.opacity(0.35)
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
    }
  }
}

/// Small, label-less square used in the `.systemMedium` strip — artwork
/// only, with the active tile ringed and showing a play/pause glyph.
private struct FavoriteStripItemView: View {
  let favorite: WidgetFavorite
  let isActive: Bool
  let isPlaying: Bool

  var body: some View {
    Button(intent: WidgetPlayFavoriteIntent(favoriteToken: favorite.token)) {
      WidgetArtwork(
        thumbnailKey: favorite.thumbnailKey, fallbackIcon: favorite.systemIconName,
        accentColor: widgetAccentColor(favorite.accentColorName)
      )
      .aspectRatio(1, contentMode: .fit)
      .overlay { if isActive { ActiveIndicator(isPlaying: isPlaying) } }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        if isActive {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white, lineWidth: 2)
            .widgetAccentable()
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(favorite.displayName)
  }
}

/// Grid tile used in `.systemLarge` — artwork only, same active-tile
/// treatment as the strip. There's no room for a name label at this size
/// once the grid holds enough tiles to be useful, so the name only appears
/// for whichever one is actually playing, in the footer below.
private struct FavoriteTileView: View {
  let favorite: WidgetFavorite
  let isActive: Bool
  let isPlaying: Bool

  var body: some View {
    Button(intent: WidgetPlayFavoriteIntent(favoriteToken: favorite.token)) {
      WidgetArtwork(
        thumbnailKey: favorite.thumbnailKey, fallbackIcon: favorite.systemIconName,
        accentColor: widgetAccentColor(favorite.accentColorName)
      )
      .aspectRatio(1, contentMode: .fit)
      .overlay { if isActive { ActiveIndicator(isPlaying: isPlaying) } }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        if isActive {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white, lineWidth: 2)
            .widgetAccentable()
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(favorite.displayName)
  }
}

/// Footer mini-player: the one thing that still gets a text label, docked at
/// the bottom of the widget rather than up top, so the grid above gets the
/// space instead of splitting it with a second card.
private struct NowPlayingFooterView: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  let playback: WidgetPlaybackState

  var body: some View {
    HStack(spacing: 8) {
      WidgetArtwork(
        thumbnailKey: playback.thumbnailKey, fallbackIcon: playback.soundSystemIconNames.first,
        accentColor: widgetAccentColor(playback.accentColorName)
      )
      .frame(width: 30, height: 30)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 0) {
        Text(playback.title)
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if let subtitle = playback.subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      Button(intent: ToggleBlankiePlaybackIntent()) {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(renderingMode == .accented ? .white : .black)
          .frame(width: 26, height: 26)
          .background(.white.opacity(renderingMode == .accented ? 0.2 : 1), in: Circle())
      }
      .buttonStyle(.plain)
    }
  }
}

private struct EmptyFavoritesView: View {
  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: "star")
        .font(.title2)
        .foregroundStyle(.white.opacity(0.6))
      Text("Star presets and sounds in Blankie to see them here.")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct FavoritesWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: FavoritesProvider.Entry

  var body: some View {
    Group {
      switch family {
      case .systemLarge:
        largeBody
      default:
        mediumBody
      }
    }
    .containerBackground(for: .widget) {
      Color("WidgetBackground")
    }
  }

  private var mediumBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(4))
    return GeometryReader { geometry in
      if shown.isEmpty {
        EmptyFavoritesView()
      } else {
        let side = max(
          0,
          min(
            geometry.size.height,
            (geometry.size.width - CGFloat(shown.count - 1) * 8) / CGFloat(shown.count)))
        HStack(spacing: 8) {
          ForEach(shown) { favorite in
            FavoriteStripItemView(
              favorite: favorite,
              isActive: favorite.token == entry.snapshot.playback.activeToken,
              isPlaying: entry.snapshot.playback.isPlaying
            )
            .frame(width: side, height: side)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var largeBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(9))
    return VStack(spacing: 8) {
      GeometryReader { geometry in
        if shown.isEmpty {
          EmptyFavoritesView()
        } else {
          // Reserve three rows even with fewer favorites, keeping sparse grids
          // at the top and tile sizes stable as favorites are added. The footer
          // takes its intrinsic height before this remaining space is measured.
          let side = max(
            0,
            min(
              (geometry.size.width - 16) / 3, (geometry.size.height - 16) / 3))
          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(side), spacing: 8), count: 3),
            spacing: 8
          ) {
            ForEach(shown) { favorite in
              FavoriteTileView(
                favorite: favorite,
                isActive: favorite.token == entry.snapshot.playback.activeToken,
                isPlaying: entry.snapshot.playback.isPlaying
              )
              .frame(width: side, height: side)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }

      NowPlayingFooterView(playback: entry.snapshot.playback)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct FavoritesWidget: Widget {
  let kind: String = "FavoritesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FavoritesProvider()) { entry in
      FavoritesWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Favorites")
    .description("Your favorited presets and sounds, plus a mini player.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

#Preview(as: .systemLarge) {
  FavoritesWidget()
} timeline: {
  FavoritesEntry(
    date: .now,
    snapshot: WidgetSnapshot(
      playback: WidgetPlaybackState(
        isPlaying: true, title: "Rainy Night", subtitle: "Rain, Thunder",
        soundSystemIconNames: ["cloud.rain.fill"], thumbnailKey: nil, activeToken: "allSounds",
        accentColorName: "blue"),
      favorites: [
        WidgetFavorite(
          token: "allSounds", displayName: "All Blankie Sounds", systemIconName: "square.grid.2x2",
          thumbnailKey: nil, accentColorName: nil, subtitle: nil)
      ],
      quickMixSounds: [],
      pinnableItems: [],
      defaultAccentColorName: "blue"))
}
