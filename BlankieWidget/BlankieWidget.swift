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
    NowPlayingEntry(date: .now, snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(NowPlayingEntry(date: .now, snapshot: WidgetStateStore.current()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    let entry = NowPlayingEntry(date: .now, snapshot: WidgetStateStore.current())
    // The app explicitly calls `WidgetCenter.reloadAllTimelines()` on every
    // playback/preset/favorites change (`WidgetStateStore.publish`), so this
    // widget doesn't need a scheduled refresh of its own.
    completion(Timeline(entries: [entry], policy: .never))
  }
}

/// Resolves a widget snapshot's `accentColorName` to a real color, falling
/// back to Blankie's own accent asset for solo sounds/Quick Mix/unset presets.
func widgetAccentColor(_ name: String?) -> Color {
  name.flatMap { Color(fromString: $0) } ?? Color("AccentColor")
}

/// The darkened accent-tinted card background shared by `NowPlayingWidget`
/// and `PinnedItemWidget`. Blends with real RGB interpolation (`Color.mix`),
/// not `.opacity()` — partially transparent gradient stops let WidgetKit's
/// own backdrop show through unpredictably (this is what made an earlier
/// "darker" attempt render lighter instead), where a fully-opaque mixed
/// color is exactly the color it looks like, regardless of what's behind it.
///
/// The Home Screen's own Light/Dark appearance is a system-level setting
/// independent of Blankie's own forced-dark in-app mode, so the widget still
/// has to respond to it: light appearance keeps the vivid accent-tinted
/// card, dark appearance blends much further toward black, matching how
/// Apple's own widgets go from a saturated card in light mode to a
/// near-black one in dark mode rather than using the same fixed background
/// in both.
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

/// Small badge carrying Blankie's own mark, for every widget that needs a
/// corner brand mark. Uses `blankie.mark`, a flattened, hole-punched render
/// of the same "B" used for the macOS menu bar icon (`blankie.symbol`) — that
/// source asset's counter is authored as separate SF Symbols motion-group
/// layers meant for animated/hierarchical rendering, which collapse into a
/// solid blob under plain flat rendering (no visible hole) the way widgets
/// render it. `blankie.mark` bakes the same hole into the path geometry
/// itself (an evenodd subpath), so it looks right with zero special-case
/// rendering — a real vector fix, not a masking trick layered on top.
struct BlankieBadge: View {
  var body: some View {
    Image("blankie.mark")
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
      .foregroundStyle(.white)
  }
}

/// Framed icon top-left, brand badge top-right, title/subtitle below, a
/// pill-shaped play/pause button below that — the same "Now Playing square"
/// shape Apple's own Shortcuts widgets (e.g. its bundled "Ambient Sounds"
/// tile) and Dark Noise's single-sound widget use: the artwork is a boxed
/// object with its own margin, never the card's own edge-to-edge background.
/// Shared by `NowPlayingWidget` and `PinnedItemWidget` so the two read as the
/// same kind of object instead of two different competing shapes.
struct NowPlayingSmallCard<PlayIntent: AppIntent>: View {
  let title: String
  let subtitle: String?
  let thumbnailKey: String?
  let fallbackIcon: String?
  let accentColor: Color
  let isPlaying: Bool
  let playIntent: PlayIntent

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        WidgetArtwork(thumbnailKey: thumbnailKey, fallbackIcon: fallbackIcon, accentColor: accentColor)
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

        Spacer()

        BlankieBadge()
      }

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.footnote.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
        }
      }

      Button(intent: playIntent) {
        HStack(spacing: 5) {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 10, weight: .bold))
          Text(isPlaying ? "Pause" : "Play")
            .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.32), in: Capsule())
        .overlay {
          Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }
    // No manual padding: WidgetKit already applies its own default content
    // margins around every widget's view (system-standard ~16pt) unless the
    // configuration opts out via `.contentMarginsDisabled()`, which this
    // doesn't. Adding padding here on top of that stacked two margins,
    // which is what was pushing the art and badge in from their true edges.
    //
    // The frame is still needed: without it the VStack sizes to its own
    // content (narrower than the widget) and gets centered in the canvas —
    // the `Spacer()` between art and badge above has nothing to expand into
    // otherwise.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// Preset artwork when a cached thumbnail exists; otherwise a bordered,
/// accent-tinted circle with the sound's own icon — the same treatment
/// `SoundIcon` uses in the app itself (`Circle().fill(accent.opacity(0.2))`
/// + an accent-colored glyph), so a solo sound looks like the same object on
/// the Home Screen as it does in the mixer, not a generic icon-on-square card.
///
/// Border width and glyph size scale off the view's own rendered size
/// (`GeometryReader`) rather than fixed points: this same view renders
/// anywhere from a 30pt footer thumbnail up to a 74pt card, and a fixed
/// 2.5pt border reads fine at 74pt but is disproportionately thick — almost
/// a solid blob — at 30pt.
struct WidgetArtwork: View {
  let thumbnailKey: String?
  let fallbackIcon: String?
  let accentColor: Color

  var body: some View {
    if let thumbnailKey, let image = thumbnailImage(forKey: thumbnailKey) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      GeometryReader { geometry in
        let side = min(geometry.size.width, geometry.size.height)
        ZStack {
          Circle()
            .fill(accentColor.opacity(0.2))
          Circle()
            .strokeBorder(accentColor, lineWidth: max(1.5, side * 0.045))
          Image(systemName: fallbackIcon ?? "waveform")
            .font(.system(size: side * 0.42, weight: .medium))
            .foregroundStyle(accentColor)
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
