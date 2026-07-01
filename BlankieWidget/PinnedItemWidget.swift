//
//  PinnedItemWidget.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Lightweight, snapshot-backed entity for the Pinned Sound widget's
/// configuration picker — reads `WidgetStateStore.current().pinnableItems`,
/// every preset and solo-able sound rather than just what's starred. Pinning
/// one specific thing to the Home Screen shouldn't require favoriting it
/// first, unlike `FavoriteControlEntity`, which is intentionally
/// starred-only.
struct PinnableItemEntity: AppEntity {
  let id: String
  var displayName: String
  var systemIconName: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Preset or Sound")
  }

  static var defaultQuery: PinnableItemEntityQuery { PinnableItemEntityQuery() }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayName)", image: .init(systemName: systemIconName))
  }
}

struct PinnableItemEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [String]) async throws -> [PinnableItemEntity] {
    let items = WidgetStateStore.current().pinnableItems
    return identifiers.compactMap { id in
      items.first { $0.token == id }.map {
        PinnableItemEntity(
          id: $0.token, displayName: $0.displayName, systemIconName: $0.systemIconName)
      }
    }
  }

  @MainActor
  func suggestedEntities() async throws -> [PinnableItemEntity] {
    WidgetStateStore.current().pinnableItems.map {
      PinnableItemEntity(
        id: $0.token, displayName: $0.displayName, systemIconName: $0.systemIconName)
    }
  }
}

struct PinnedItemConfigurationIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Choose Preset or Sound" }
  static var description: IntentDescription {
    IntentDescription("Pick any preset or sound to pin.")
  }

  @Parameter(title: "Preset or Sound")
  var item: PinnableItemEntity?
}

struct PinnedItemEntry: TimelineEntry {
  let date: Date
  let item: WidgetFavorite?
  let isActive: Bool
  let isPlaying: Bool
}

struct PinnedItemProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PinnedItemEntry {
    PinnedItemEntry(date: .now, item: nil, isActive: false, isPlaying: false)
  }

  func snapshot(for configuration: PinnedItemConfigurationIntent, in context: Context) async
    -> PinnedItemEntry
  {
    entry(for: configuration)
  }

  func timeline(for configuration: PinnedItemConfigurationIntent, in context: Context) async
    -> Timeline<PinnedItemEntry>
  {
    Timeline(entries: [entry(for: configuration)], policy: .never)
  }

  @MainActor
  private func entry(for configuration: PinnedItemConfigurationIntent) -> PinnedItemEntry {
    let snapshot = WidgetStateStore.current()
    let item = snapshot.pinnableItems.first { $0.token == configuration.item?.id }
    let isActive = item != nil && item?.token == snapshot.playback.activeToken
    return PinnedItemEntry(
      date: .now, item: item, isActive: isActive, isPlaying: snapshot.playback.isPlaying)
  }
}

/// Uses the same `NowPlayingSmallCard` shape and background treatment
/// `NowPlayingWidget` does — a pinned preset/sound and whatever's currently
/// playing are the same kind of object, so they read as the same widget
/// family instead of two competing card designs. Small only: a pinned
/// item's whole point is a single glanceable shortcut, and the medium
/// layout (framed art + text + a plain circular button, no badge) reads as
/// a different, weaker version of the same idea rather than a genuinely
/// useful larger size.
struct PinnedItemWidgetEntryView: View {
  @Environment(\.colorScheme) private var colorScheme
  var entry: PinnedItemProvider.Entry

  var body: some View {
    if let item = entry.item {
      let accent = widgetAccentColor(item.accentColorName)
      let isPlaying = entry.isActive && entry.isPlaying

      NowPlayingSmallCard(
        title: item.displayName, subtitle: item.subtitle,
        thumbnailKey: item.thumbnailKey, fallbackIcon: item.systemIconName, accentColor: accent,
        isPlaying: isPlaying, playIntent: WidgetPlayFavoriteIntent(favoriteToken: item.token)
      )
      .containerBackground(for: .widget) {
        widgetAccentGradient(accent, colorScheme: colorScheme)
      }
    } else {
      VStack(spacing: 6) {
        Image(systemName: "pin")
          .font(.title2)
          .foregroundStyle(.white.opacity(0.6))
        Text("Choose a preset or sound to pin")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.6))
          .multilineTextAlignment(.center)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .containerBackground(for: .widget) {
        Color("WidgetBackground")
      }
    }
  }
}

struct PinnedItemWidget: Widget {
  let kind: String = "PinnedItemWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind, intent: PinnedItemConfigurationIntent.self, provider: PinnedItemProvider()
    ) { entry in
      PinnedItemWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Pinned Sound")
    .description("Pin one preset or sound to your Home Screen.")
    .supportedFamilies([.systemSmall])
  }
}

#Preview(as: .systemSmall) {
  PinnedItemWidget()
} timeline: {
  PinnedItemEntry(
    date: .now,
    item: WidgetFavorite(
      token: "abc", displayName: "Deep Focus", systemIconName: "square.stack.3d.up.fill",
      thumbnailKey: nil, accentColorName: "purple", subtitle: "Rain, Thunder"),
    isActive: true, isPlaying: true)
}
