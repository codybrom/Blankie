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
  var color: WidgetColorChoice = .defaultAccent
}

struct FavoritesProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> FavoritesEntry {
    FavoritesEntry(date: .now, snapshot: .galleryPreview)
  }

  func snapshot(for configuration: WidgetAppearanceIntent, in context: Context) async
    -> FavoritesEntry
  {
    FavoritesEntry(
      date: .now, snapshot: context.isPreview ? .galleryPreview : WidgetStateStore.current(),
      color: configuration.color)
  }

  func timeline(for configuration: WidgetAppearanceIntent, in context: Context) async
    -> Timeline<FavoritesEntry>
  {
    let entry = FavoritesEntry(
      date: .now, snapshot: WidgetStateStore.current(), color: configuration.color)
    return Timeline(entries: [entry], policy: .never)
  }
}

/// Play/pause glyph on the tile matching the active token, so a tap reads as pause.
private struct ActiveIndicator: View {
  let isPlaying: Bool
  var isSound: Bool = false

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black.opacity(0.35)
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
        if isSound {
          Circle()
            .strokeBorder(
              .white,
              lineWidth: max(1.5, min(geometry.size.width, geometry.size.height) * 0.045))
        }
      }
    }
  }
}

/// Labeled buttons for medium Favorites, matching large Quick Mix's rows.
private struct FavoriteRowView: View {
  @Environment(\.widgetForeground) private var foreground
  @Environment(\.widgetRenderingMode) private var renderingMode
  let favorite: WidgetFavorite
  let accent: Color
  let isActive: Bool
  let isPlaying: Bool
  var artworkSize: CGFloat = 36
  var showsSubtitle: Bool = false
  var usesSelectionBorder: Bool = true

  var body: some View {
    Button(intent: WidgetPlayFavoriteIntent(favoriteToken: favorite.token)) {
      HStack(spacing: 8) {
        WidgetArtwork(
          thumbnailKey: favorite.thumbnailKey, fallbackIcon: favorite.systemIconName,
          accentColor: widgetAccentColor(favorite.accentColorName),
          borderColor: isActive && usesSelectionBorder && favorite.isSingleSound
            ? .white : nil,
          showsFallbackIcon: !(isActive && usesSelectionBorder && favorite.isSingleSound)
        )
        .frame(width: artworkSize, height: artworkSize)
        .overlay {
          if isActive {
            ActiveIndicator(
              isPlaying: isPlaying,
              isSound: usesSelectionBorder && favorite.isSingleSound)
          }
        }
        .clipShape(
          favorite.thumbnailKey == nil
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))

        VStack(alignment: .leading, spacing: 3) {
          Text(favorite.displayName)
            .font(showsSubtitle ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
            .lineLimit(2)
          if showsSubtitle, let subtitle = favorite.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .opacity(0.65)
              .lineLimit(2)
          }
        }
        .foregroundStyle(
          isActive
            ? (renderingMode == .accented ? .white : accent.contrastingLabel) : foreground
        )
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        isActive
          ? (renderingMode == .accented
            ? Color.white.opacity(0.3) : accent)
          : foreground.opacity(0.10),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .widgetAccentable(isActive)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(favorite.displayName)
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

/// Artwork-led card for a single favorite.
private struct SingleFavoriteView: View {
  @Environment(\.widgetForeground) private var foreground
  let favorite: WidgetFavorite
  let isActive: Bool
  let isPlaying: Bool

  var body: some View {
    GeometryReader { geometry in
      let side = min(geometry.size.height, geometry.size.width * 0.38)
      Button(intent: WidgetPlayFavoriteIntent(favoriteToken: favorite.token)) {
        HStack(spacing: 14) {
          WidgetArtwork(
            thumbnailKey: favorite.thumbnailKey, fallbackIcon: favorite.systemIconName,
            accentColor: widgetAccentColor(favorite.accentColorName),
            borderColor: isActive && favorite.isSingleSound ? .white : nil,
            showsFallbackIcon: !(isActive && favorite.isSingleSound)
          )
          .frame(width: side, height: side)
          .overlay {
            if isActive && favorite.isSingleSound {
              ActiveIndicator(isPlaying: isPlaying, isSound: true)
            }
          }
          .clipShape(
            favorite.thumbnailKey == nil
              ? AnyShape(Circle())
              : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))

          VStack(alignment: .leading, spacing: 5) {
            Text(favorite.displayName)
              .font(.headline)
              .foregroundStyle(foreground)
              .lineLimit(2)
            if let subtitle = favorite.subtitle, !subtitle.isEmpty {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(foreground.opacity(0.65))
                .lineLimit(2)
            }
            if !(isActive && favorite.isSingleSound) {
              Image(systemName: isActive && isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(foreground)
                .padding(.top, 3)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(favorite.displayName)
      .accessibilityAddTraits(isActive ? .isSelected : [])
    }
  }
}

/// Artwork tiles fill balanced rows in the large widget.
private struct FavoriteTileView: View {
  let favorite: WidgetFavorite
  let isActive: Bool
  let isPlaying: Bool

  var body: some View {
    Button(intent: WidgetPlayFavoriteIntent(favoriteToken: favorite.token)) {
      GeometryReader { geometry in
        let shape =
          favorite.thumbnailKey == nil
          ? AnyShape(Circle())
          : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let width =
          favorite.thumbnailKey == nil
          ? min(geometry.size.width, geometry.size.height) : geometry.size.width
        let height = favorite.thumbnailKey == nil ? width : geometry.size.height
        WidgetArtwork(
          thumbnailKey: favorite.thumbnailKey, fallbackIcon: favorite.systemIconName,
          accentColor: widgetAccentColor(favorite.accentColorName)
        )
        .frame(width: width, height: height)
        .overlay {
          if isActive {
            ActiveIndicator(isPlaying: isPlaying)
          }
        }
        .clipShape(shape)
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(favorite.displayName)
  }
}

/// Footer mini-player, docked at the bottom so the tiles get the space above.
private struct NowPlayingFooterView: View {
  @Environment(\.widgetForeground) private var foreground
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
          .foregroundStyle(foreground)
          .lineLimit(1)
        if let subtitle = playback.subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(foreground.opacity(0.6))
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
  @Environment(\.widgetForeground) private var foreground
  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: "star")
        .font(.title2)
        .foregroundStyle(foreground.opacity(0.6))
      Text("Star presets and sounds in Blankie to see them here.")
        .font(.caption)
        .foregroundStyle(foreground.opacity(0.6))
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
      if family.isExtraLargePortrait {
        extraLargeBody
      } else if family == .systemLarge {
        largeBody
      } else {
        mediumBody
      }
    }
    .environment(\.widgetForeground, .white)
    .containerBackground(for: .widget) {
      WidgetAppearanceBackground(
        choice: entry.color, defaultAccentName: entry.snapshot.defaultAccentColorName)
    }
  }

  private var mediumBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(4))
    return GeometryReader { geometry in
      if shown.isEmpty {
        EmptyFavoritesView()
      } else if shown.count == 1, let favorite = shown.first {
        SingleFavoriteView(
          favorite: favorite,
          isActive: favorite.token == entry.snapshot.playback.activeToken,
          isPlaying: entry.snapshot.playback.isPlaying)
      } else {
        let rows = (shown.count + 1) / 2
        let height = max(0, (geometry.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows))
        VStack(spacing: 8) {
          ForEach(0..<rows, id: \.self) { row in
            HStack(spacing: 8) {
              ForEach(Array(shown.dropFirst(row * 2).prefix(2))) { favorite in
                FavoriteRowView(
                  favorite: favorite,
                  accent: entry.color.accent(defaultName: entry.snapshot.defaultAccentColorName),
                  isActive: favorite.token == entry.snapshot.playback.activeToken,
                  isPlaying: entry.snapshot.playback.isPlaying
                )
              }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
          }
        }
      }
    }
  }

  /// Row sizes that avoid a lone tile on the last row.
  private func favoriteRowCounts(for count: Int) -> [Int] {
    switch count {
    case 1...3: [count]
    case 4: [2, 2]
    case 5: [3, 2]
    case 6: [3, 3]
    case 7: [2, 3, 2]
    case 8: [3, 2, 3]
    default: [3, 3, 3]
    }
  }

  private var extraLargeBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(12))
    return VStack(spacing: 12) {
      HStack(spacing: 8) {
        BlankieBadge()
        Text("Favorites")
          .font(.headline)
          .foregroundStyle(.white)
        Spacer(minLength: 0)
      }
      .fixedSize(horizontal: false, vertical: true)

      GeometryReader { geometry in
        if shown.isEmpty {
          EmptyFavoritesView()
        } else if shown.count == 1, let favorite = shown.first {
          VStack(spacing: 10) {
            FavoriteTileView(
              favorite: favorite,
              isActive: favorite.token == entry.snapshot.playback.activeToken,
              isPlaying: entry.snapshot.playback.isPlaying)
            Text(favorite.displayName)
              .font(.headline)
              .foregroundStyle(.white)
              .lineLimit(2)
          }
        } else {
          let columns = shown.count <= 6 ? 1 : 2
          let rows = (shown.count + columns - 1) / columns
          let height = max(0, (geometry.size.height - CGFloat(rows - 1) * 8) / CGFloat(rows))
          let artworkSize = min(columns == 1 ? 88.0 : 44.0, max(30, height - 16))
          VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
              HStack(spacing: 8) {
                ForEach(Array(shown.dropFirst(row * columns).prefix(columns))) { favorite in
                  FavoriteRowView(
                    favorite: favorite,
                    accent: entry.color.accent(defaultName: entry.snapshot.defaultAccentColorName),
                    isActive: favorite.token == entry.snapshot.playback.activeToken,
                    isPlaying: entry.snapshot.playback.isPlaying,
                    artworkSize: artworkSize, showsSubtitle: columns == 1,
                    usesSelectionBorder: false)
                }
              }
              .frame(maxWidth: .infinity)
              .frame(height: height)
            }
          }
        }
      }
      NowPlayingFooterView(playback: entry.snapshot.playback)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var largeBody: some View {
    let shown = Array(entry.snapshot.favorites.prefix(9))
    return VStack(spacing: 8) {
      GeometryReader { geometry in
        if shown.isEmpty {
          EmptyFavoritesView()
        } else {
          let rowCounts = favoriteRowCounts(for: shown.count)
          let height = max(
            0, (geometry.size.height - CGFloat(rowCounts.count - 1) * 8) / CGFloat(rowCounts.count))
          VStack(spacing: 8) {
            ForEach(rowCounts.indices, id: \.self) { row in
              let count = rowCounts[row]
              let start = rowCounts.prefix(row).reduce(0, +)
              let width = max(0, (geometry.size.width - CGFloat(count - 1) * 8) / CGFloat(count))
              HStack(spacing: 8) {
                ForEach(Array(shown.dropFirst(start).prefix(count))) { favorite in
                  FavoriteTileView(
                    favorite: favorite,
                    isActive: favorite.token == entry.snapshot.playback.activeToken,
                    isPlaying: entry.snapshot.playback.isPlaying
                  )
                  .frame(width: width, height: height)
                }
              }
              .frame(width: geometry.size.width, height: height)
            }
          }
          .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
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
    AppIntentConfiguration(
      kind: kind, intent: WidgetAppearanceIntent.self, provider: FavoritesProvider()
    ) { entry in
      FavoritesWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Favorites")
    .description("Your favorited presets and sounds, plus a mini player.")
    .supportedFamilies(interactiveWidgetFamilies)
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
