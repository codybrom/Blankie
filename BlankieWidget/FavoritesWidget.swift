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
    FavoritesEntry(date: .now, snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
    completion(FavoritesEntry(date: .now, snapshot: WidgetStateStore.current()))
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
        }
      }
    }
    .buttonStyle(.plain)
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
        }
      }
    }
    .buttonStyle(.plain)
  }
}

/// Footer mini-player: the one thing that still gets a text label, docked at
/// the bottom of the widget rather than up top, so the grid above gets the
/// space instead of splitting it with a second card.
private struct NowPlayingFooterView: View {
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
          .foregroundStyle(.black)
          .frame(width: 26, height: 26)
          .background(.white, in: Circle())
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

  // `.systemMedium` has roughly 155pt of height total — not enough for a
  // grid plus a separate now-playing row, which is what made this size look
  // broken before. Artwork only, single row, no text at all: the active tile
  // (if any) is marked directly, so there's nothing else to make room for.
  private var mediumBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(4))
    return Group {
      if shown.isEmpty {
        EmptyFavoritesView()
      } else {
        HStack(spacing: 8) {
          ForEach(shown) { favorite in
            FavoriteStripItemView(
              favorite: favorite,
              isActive: favorite.token == entry.snapshot.playback.activeToken,
              isPlaying: entry.snapshot.playback.isPlaying)
          }
        }
      }
    }
    .padding(10)
  }

  private var largeBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(9))
    return VStack(spacing: 8) {
      if shown.isEmpty {
        EmptyFavoritesView()
      } else {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
          spacing: 8
        ) {
          ForEach(shown) { favorite in
            FavoriteTileView(
              favorite: favorite,
              isActive: favorite.token == entry.snapshot.playback.activeToken,
              isPlaying: entry.snapshot.playback.isPlaying)
          }
        }
      }

      NowPlayingFooterView(playback: entry.snapshot.playback)
    }
    .padding(10)
  }
}

struct FavoritesWidget: Widget {
  let kind: String = "FavoritesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FavoritesProvider()) { entry in
      FavoritesWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Favorites")
    .description("Your favorited presets, Quick Mix, and sounds, plus a mini player.")
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
          thumbnailKey: nil, accentColorName: nil, subtitle: nil),
        WidgetFavorite(
          token: "quickMix", displayName: "Quick Mix", systemIconName: "shuffle", thumbnailKey: nil,
          accentColorName: nil, subtitle: nil),
      ],
      quickMixSounds: [],
      pinnableItems: [],
      defaultAccentColorName: "blue"))
}
