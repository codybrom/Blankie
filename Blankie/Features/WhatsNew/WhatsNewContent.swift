//
//  WhatsNewContent.swift
//  Blankie
//
//  Created by Cody Bromley on 10/28/26.
//

import Foundation

/// One release's highlights on the What's New page.
struct WhatsNewRelease: Identifiable {
  let version: String
  let items: [WhatsNewItem]
  var id: String { version }
}

struct WhatsNewItem: Identifiable {
  let systemImage: String
  let title: String
  let detail: String
  var id: String { title }
}

/// Release highlights, newest first. Written in English only and kept out of the
/// string catalog: WhatsNewView translates them on device for other languages.
/// Adding a release here badges the Settings gear until its page is opened.
enum WhatsNew {
  static let releases: [WhatsNewRelease] = [
    WhatsNewRelease(version: "2.1.1", items: items211),
    WhatsNewRelease(version: "2.1", items: items21),
  ]

  static var latestVersion: String { releases[0].version }

  /// True until the user opens the newest release's page.
  static func hasUnseen(lastSeen: String?) -> Bool {
    guard let lastSeen else { return true }
    return latestVersion.compare(lastSeen, options: .numeric) == .orderedDescending
  }

  /// Every title and detail, for one batch translation.
  static var allText: [String] {
    releases.flatMap { $0.items.flatMap { [$0.title, $0.detail] } }
  }

  private static var items211: [WhatsNewItem] {
    var items = [
      WhatsNewItem(
        systemImage: "sparkles", title: "What's New, right here",
        detail:
          "Each update's highlights now live in Settings. If Blankie is set to another language, they're translated right on your device."
      ),
      WhatsNewItem(
        systemImage: "waveform.low", title: "Brown Noise in your language",
        detail:
          "Brown Noise now goes by its own name in every language Blankie supports, with a new subtitle: \"Deep, smooth rumble.\""
      ),
    ]
    #if os(macOS)
      items.append(
        WhatsNewItem(
          systemImage: "wrench.and.screwdriver", title: "Fixes",
          detail: "First-run setup and the sound credits in About now sort sounds in your language."
        ))
    #else
      items.append(
        WhatsNewItem(
          systemImage: "wrench.and.screwdriver", title: "Fixes",
          detail:
            "A Pause button left showing on a widget after Blankie closed no longer starts playback, and first-run setup sorts sounds in your language."
        ))
    #endif
    return items
  }

  private static var items21: [WhatsNewItem] {
    #if os(macOS)
      [
        WhatsNewItem(
          systemImage: "square.stack.3d.up", title: "Shortcuts and Spotlight",
          detail:
            "Use Blankie in the Shortcuts app to play or pause, start a preset or sound, set a sleep timer or change the volume. Find your presets and sounds in Spotlight."
        ),
        WhatsNewItem(
          systemImage: "photo.on.rectangle", title: "Preset artwork on the Mac",
          detail:
            "A preset's background artwork now shows behind your sound tiles, dimmed so they stay readable."
        ),
        WhatsNewItem(
          systemImage: "captions.bubble", title: "Sound subtitles",
          detail:
            "Every built-in sound now has a short subtitle (\"Soft, steady rainfall\") that tells you what you're about to hear."
        ),
        WhatsNewItem(
          systemImage: "wrench.and.screwdriver", title: "Fixes",
          detail:
            "Fixes for playback, the sleep timer, preset imports, custom sounds, the window background, Autoplay on Open and the menu bar icon."
        ),
      ]
    #else
      [
        WhatsNewItem(
          systemImage: "widget.small", title: "Home Screen widgets",
          detail:
            "Start a favorite, Quick Mix or a single sound in one tap, or play and pause from Now Playing."
        ),
        WhatsNewItem(
          systemImage: "mic.fill", title: "Siri, Shortcuts and Spotlight",
          detail:
            "Ask Siri to play a preset or sound, build your own actions in the Shortcuts app, and find your presets in Spotlight."
        ),
        WhatsNewItem(
          systemImage: "rectangle.split.2x1", title: "Support for iPhone Duo",
          detail:
            "Now Playing on one screen and the Sound Mixer on the other, in any pose. Fold or close it and you keep your place."
        ),
        WhatsNewItem(
          systemImage: "play.circle", title: "Now Playing opens first on iPhone",
          detail:
            "Picking a preset or sound now takes you to what's playing, and Quick Mix still opens to its tiles. To go straight to the mixer instead, turn off Open to Now Playing in Settings."
        ),
        WhatsNewItem(
          systemImage: "ipad.landscape", title: "Wider layout on iPad",
          detail:
            "A preset's page now shows its artwork at the top. Preset and sound editors open in a side panel (iPadOS 27), so the page you're changing stays in view."
        ),
        WhatsNewItem(
          systemImage: "captions.bubble", title: "Sound subtitles",
          detail:
            "Every built-in sound now has a short subtitle (\"Soft, steady rainfall\"), shown in the app, on the Lock Screen and in CarPlay."
        ),
        WhatsNewItem(
          systemImage: "wrench.and.screwdriver", title: "Fixes",
          detail:
            "Fixes for playback, the sleep timer, preset imports, custom sounds, CarPlay and the Lock Screen."
        ),
      ]
    #endif
  }
}
